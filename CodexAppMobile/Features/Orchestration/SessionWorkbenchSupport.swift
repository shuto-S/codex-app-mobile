import Foundation

struct SSHCodexExecResult {
    let threadID: String
    let assistantText: String
}

enum SSHCodexExecError: LocalizedError {
    case timeout
    case malformedOutput
    case noResponse
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .timeout:
            return "codex exec timed out on remote host."
        case .malformedOutput:
            return "Could not parse codex exec output from remote host."
        case .noResponse:
            return "codex exec completed without a readable response."
        case .commandFailed(let message):
            return message
        }
    }
}

actor SSHCodexExecService {
    func checkCodexVersion(host: RemoteHost, password: String) async throws -> String {
        let output = try await self.runRemoteCommand(
            host: host,
            password: password,
            command: "codex --version",
            timeoutSeconds: 20
        )
        let lines = Self.nonEmptyLines(from: output)
        guard let versionLine = lines.first(where: { $0.lowercased().contains("codex") }) ?? lines.first else {
            throw SSHCodexExecError.noResponse
        }
        return versionLine
    }

    func executePrompt(
        host: RemoteHost,
        password: String,
        workspacePath: String,
        prompt: String,
        resumeThreadID: String?,
        forceNewThread: Bool,
        model: String?
    ) async throws -> SSHCodexExecResult {
        let command = Self.buildExecCommand(
            workspacePath: workspacePath,
            prompt: prompt,
            resumeThreadID: resumeThreadID,
            forceNewThread: forceNewThread,
            model: model
        )
        let output = try await self.runRemoteCommand(
            host: host,
            password: password,
            command: command,
            timeoutSeconds: 300
        )
        return try Self.parseExecResult(output: output, fallbackThreadID: resumeThreadID)
    }

    private func runRemoteCommand(
        host: RemoteHost,
        password: String,
        command: String,
        timeoutSeconds: Int
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let queue = DispatchQueue(label: "com.example.CodexAppMobile.ssh-codex-exec")
            queue.async {
                final class SharedState: @unchecked Sendable {
                    var fullOutput = ""
                    var completed = false
                }

                let state = SharedState()
                let engine = SSHClientEngine()
                let startMarker = "__CODEX_EXEC_START__"
                let endMarker = "__CODEX_EXEC_END__"
                let connectTimeoutSeconds = min(20, max(5, timeoutSeconds))

                let timeoutSource = DispatchSource.makeTimerSource(queue: queue)
                timeoutSource.schedule(deadline: .now() + .seconds(connectTimeoutSeconds))
                timeoutSource.setEventHandler {
                    guard !state.completed else { return }
                    state.completed = true
                    engine.disconnect()
                    continuation.resume(throwing: SSHCodexExecError.timeout)
                }
                timeoutSource.resume()

                let complete: @Sendable (Result<String, Error>) -> Void = { result in
                    guard !state.completed else { return }
                    state.completed = true
                    timeoutSource.cancel()
                    engine.disconnect()
                    continuation.resume(with: result)
                }

                engine.onOutput = { chunk in
                    queue.async {
                        guard !state.completed else { return }
                        state.fullOutput += chunk
                        guard state.fullOutput.contains(endMarker) else { return }
                        do {
                            let parsed = try Self.parseDelimitedOutput(
                                state.fullOutput,
                                startMarker: startMarker,
                                endMarker: endMarker
                            )
                            complete(.success(parsed))
                        } catch {
                            complete(.failure(error))
                        }
                    }
                }

                engine.onError = { error in
                    queue.async {
                        complete(.failure(error))
                    }
                }

                engine.onConnected = {
                    queue.async {
                        guard !state.completed else { return }
                        timeoutSource.schedule(deadline: .now() + .seconds(timeoutSeconds))

                        let wrappedCommand = "printf '\(startMarker)\\n'; \(command) 2>&1; printf '\\n\(endMarker)\\n'"
                        do {
                            try engine.send(command: wrappedCommand + "\n")
                        } catch {
                            complete(.failure(error))
                        }
                    }
                }

                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try engine.connect(
                            host: host.host,
                            port: host.sshPort,
                            username: host.username,
                            password: password.isEmpty ? nil : password
                        )
                    } catch {
                        queue.async {
                            complete(.failure(error))
                        }
                    }
                }
            }
        }
    }

    private static func buildExecCommand(
        workspacePath: String,
        prompt: String,
        resumeThreadID: String?,
        forceNewThread: Bool,
        model: String?
    ) -> String {
        let escapedPath = self.escapeForSingleQuote(workspacePath)
        let escapedPrompt = self.escapeForSingleQuote(prompt)
        let trimmedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let modelArgument: String
        if trimmedModel.isEmpty {
            modelArgument = ""
        } else {
            modelArgument = " --model '\(self.escapeForSingleQuote(trimmedModel))'"
        }

        if !forceNewThread,
           let resumeThreadID,
           !resumeThreadID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let escapedThreadID = self.escapeForSingleQuote(resumeThreadID)
            return "cd '\(escapedPath)' && codex exec resume --json --skip-git-repo-check\(modelArgument) '\(escapedThreadID)' '\(escapedPrompt)'"
        }

        return "cd '\(escapedPath)' && codex exec --json --skip-git-repo-check\(modelArgument) '\(escapedPrompt)'"
    }

    private static func parseDelimitedOutput(
        _ output: String,
        startMarker: String,
        endMarker: String
    ) throws -> String {
        guard let startRange = output.range(of: startMarker),
              let endRange = output.range(of: endMarker),
              startRange.upperBound <= endRange.lowerBound
        else {
            throw SSHCodexExecError.malformedOutput
        }

        return String(output[startRange.upperBound..<endRange.lowerBound])
    }

    private static func parseExecResult(output: String, fallbackThreadID: String?) throws -> SSHCodexExecResult {
        var resolvedThreadID = fallbackThreadID
        var assistantChunks: [String] = []
        var errorLines: [String] = []
        var nonJSONLines: [String] = []

        for line in self.nonEmptyLines(from: output) {
            guard line.hasPrefix("{"),
                  let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = object["type"] as? String else {
                nonJSONLines.append(line)
                if line.lowercased().contains("error") {
                    errorLines.append(line)
                }
                continue
            }

            switch type {
            case "thread.started":
                if let threadID = object["thread_id"] as? String,
                   !threadID.isEmpty {
                    resolvedThreadID = threadID
                }
            case "item.completed":
                guard let item = object["item"] as? [String: Any],
                      let itemType = item["type"] as? String else {
                    continue
                }
                if itemType == "agent_message",
                   let text = item["text"] as? String,
                   !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    assistantChunks.append(text)
                }
            case "error":
                if let message = object["message"] as? String,
                   !message.isEmpty {
                    errorLines.append(message)
                }
            default:
                continue
            }
        }

        if !errorLines.isEmpty && assistantChunks.isEmpty {
            throw SSHCodexExecError.commandFailed(errorLines.joined(separator: "\n"))
        }

        let assistantText: String
        if assistantChunks.isEmpty {
            assistantText = nonJSONLines.joined(separator: "\n")
        } else {
            assistantText = assistantChunks.joined(separator: "\n")
        }

        let trimmedText = assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw SSHCodexExecError.noResponse
        }

        let threadID = resolvedThreadID ?? UUID().uuidString
        return SSHCodexExecResult(threadID: threadID, assistantText: trimmedText)
    }

    private static func nonEmptyLines(from text: String) -> [String] {
        text
            .split(whereSeparator: \.isNewline)
            .map { self.stripANSI(String($0)).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func escapeForSingleQuote(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "'\"'\"'")
    }

    private static func stripANSI(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"\u{001B}\[[0-9;?]*[ -/]*[@-~]"#,
            with: "",
            options: .regularExpression
        )
    }
}

enum SessionChatRole {
    case user
    case assistant
}

struct SessionChatMessage: Identifiable, Equatable {
    let id: String
    let role: SessionChatRole
    let text: String
    let isProgressDetail: Bool
}
