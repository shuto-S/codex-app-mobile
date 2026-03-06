import Foundation
import OSLog

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

enum GitMenuAction: String, CaseIterable, Identifiable {
    case commit
    case commitAndPush
    case push
    case diff

    var id: String { self.rawValue }

    var title: String {
        switch self {
        case .commit:
            return "Commit"
        case .commitAndPush:
            return "Commit+Push"
        case .push:
            return "Push"
        case .diff:
            return "Diff"
        }
    }

    var systemImage: String {
        switch self {
        case .commit:
            return "checkmark.circle"
        case .commitAndPush:
            return "arrow.up.doc"
        case .push:
            return "arrow.up.circle"
        case .diff:
            return "doc.text.magnifyingglass"
        }
    }
}

enum GitModalAction: String, CaseIterable, Identifiable {
    case commit
    case commitAndPush
    case push

    var id: String { self.rawValue }

    var title: String {
        switch self {
        case .commit:
            return "Commit"
        case .commitAndPush:
            return "Commit+Push"
        case .push:
            return "Push"
        }
    }

    var actionButtonTitle: String {
        switch self {
        case .commit:
            return "Run Commit"
        case .commitAndPush:
            return "Run Commit+Push"
        case .push:
            return "Run Push"
        }
    }

    var requiresCommitMessage: Bool {
        switch self {
        case .commit, .commitAndPush:
            return true
        case .push:
            return false
        }
    }
}

struct GitDiffSummary: Equatable {
    let branchName: String
    let changedFiles: Int
    let untrackedFiles: Int
    let additions: Int?
    let deletions: Int?

    var hasLineTotals: Bool {
        self.additions != nil && self.deletions != nil
    }
}

enum GitDiffLineKind: Equatable {
    case context
    case addition
    case deletion
    case meta
}

struct GitDiffLine: Identifiable, Equatable {
    let id: String
    let kind: GitDiffLineKind
    let oldLineNumber: Int?
    let newLineNumber: Int?
    let text: String
}

struct GitDiffHunk: Identifiable, Equatable {
    let id: String
    let header: String
    let lines: [GitDiffLine]
}

struct GitDiffFile: Identifiable, Equatable {
    let id: String
    let displayPath: String
    let oldPath: String?
    let newPath: String?
    let metadata: [String]
    let hunks: [GitDiffHunk]
    let isBinary: Bool
}

struct GitDiffSnapshot: Equatable {
    let summary: GitDiffSummary
    let files: [GitDiffFile]
}

struct GitPushResult: Equatable {
    let usedUpstreamFallback: Bool
    let output: String
}

enum SSHGitServiceError: LocalizedError {
    case timeout
    case malformedOutput
    case commandFailed(String)
    case invalidCurrentBranch
    case noDiffAvailable
    case codexExecFailed(String)
    case codexExecNoMessage

    var errorDescription: String? {
        switch self {
        case .timeout:
            return "Git command timed out on remote host."
        case .malformedOutput:
            return "Could not parse remote command output."
        case .commandFailed(let message):
            return message
        case .invalidCurrentBranch:
            return "Current branch is detached. Push requires a branch name."
        case .noDiffAvailable:
            return "No staged changes available to generate a commit message."
        case .codexExecFailed(let message):
            return message
        case .codexExecNoMessage:
            return "codex exec completed without a commit message."
        }
    }
}

private struct SSHGitCommandResult {
    let output: String
    let exitCode: Int
}

actor SSHGitService {
    private static let logger = Logger(
        subsystem: "com.example.CodexAppMobile",
        category: "SSHGitService"
    )

    func loadDiff(
        host: RemoteHost,
        password: String,
        workspacePath: String
    ) async throws -> GitDiffSnapshot {
        let branchName: String
        do {
            branchName = try await self.resolveCurrentBranchName(
                host: host,
                password: password,
                workspacePath: workspacePath
            )
        } catch {
            branchName = "HEAD"
            Self.logger.debug(
                "SSHGit fallback branch name to HEAD error=\(String(describing: error), privacy: .public)"
            )
        }

        let diffBaseRef = try await self.resolveDiffBaseReference(
            host: host,
            password: password,
            workspacePath: workspacePath
        )

        let numstatResult = try await self.runWorkspaceCommand(
            host: host,
            password: password,
            workspacePath: workspacePath,
            command: Self.gitNoPagerCommand("diff --numstat --find-renames \(diffBaseRef) -- ."),
            timeoutSeconds: 40
        )
        guard numstatResult.exitCode == 0 else {
            throw SSHGitServiceError.commandFailed(
                Self.bestFailureMessage(output: numstatResult.output, exitCode: numstatResult.exitCode)
            )
        }

        let statusResult = try await self.runWorkspaceCommand(
            host: host,
            password: password,
            workspacePath: workspacePath,
            command: Self.gitNoPagerCommand("status --porcelain=v1 --untracked-files=all"),
            timeoutSeconds: 40
        )
        guard statusResult.exitCode == 0 else {
            throw SSHGitServiceError.commandFailed(
                Self.bestFailureMessage(output: statusResult.output, exitCode: statusResult.exitCode)
            )
        }

        let patchResult = try await self.runWorkspaceCommand(
            host: host,
            password: password,
            workspacePath: workspacePath,
            command: Self.gitNoPagerCommand("diff --patch --no-color --find-renames \(diffBaseRef) -- ."),
            timeoutSeconds: 80
        )
        guard patchResult.exitCode == 0 else {
            throw SSHGitServiceError.commandFailed(
                Self.bestFailureMessage(output: patchResult.output, exitCode: patchResult.exitCode)
            )
        }

        let files = try Self.parseDiffFiles(patchResult.output)
        let patchTotals = Self.patchLineTotals(from: files)
        let numstat = Self.parseNumstatSummary(numstatResult.output)
        let untrackedCount = Self.untrackedFileCount(fromStatus: statusResult.output)
        let trackedChangedFiles = max(numstat.fileCount, files.count)

        var additions = numstat.additions
        var deletions = numstat.deletions
        if additions == nil || deletions == nil {
            if patchTotals.available {
                additions = patchTotals.additions
                deletions = patchTotals.deletions
            } else {
                additions = nil
                deletions = nil
            }
        }

        let summary = GitDiffSummary(
            branchName: branchName,
            changedFiles: trackedChangedFiles + untrackedCount,
            untrackedFiles: untrackedCount,
            additions: additions,
            deletions: deletions
        )

        return GitDiffSnapshot(summary: summary, files: files)
    }

    func stageAll(
        host: RemoteHost,
        password: String,
        workspacePath: String
    ) async throws {
        let result = try await self.runWorkspaceCommand(
            host: host,
            password: password,
            workspacePath: workspacePath,
            command: "git add -A",
            timeoutSeconds: 40
        )
        guard result.exitCode == 0 else {
            throw SSHGitServiceError.commandFailed(
                Self.bestFailureMessage(output: result.output, exitCode: result.exitCode)
            )
        }
    }

    func commit(
        host: RemoteHost,
        password: String,
        workspacePath: String,
        message: String
    ) async throws {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            throw SSHGitServiceError.codexExecNoMessage
        }
        let escapedMessage = Self.escapeForSingleQuote(trimmedMessage)
        let result = try await self.runWorkspaceCommand(
            host: host,
            password: password,
            workspacePath: workspacePath,
            command: "git commit -m '\(escapedMessage)'",
            timeoutSeconds: 90
        )
        guard result.exitCode == 0 else {
            throw SSHGitServiceError.commandFailed(
                Self.bestFailureMessage(output: result.output, exitCode: result.exitCode)
            )
        }
    }

    func pushWithUpstreamFallback(
        host: RemoteHost,
        password: String,
        workspacePath: String
    ) async throws -> GitPushResult {
        let initial = try await self.runWorkspaceCommand(
            host: host,
            password: password,
            workspacePath: workspacePath,
            command: "git push",
            timeoutSeconds: 120
        )
        if initial.exitCode == 0 {
            return GitPushResult(usedUpstreamFallback: false, output: initial.output)
        }

        guard Self.isUpstreamNotSetError(initial.output) else {
            throw SSHGitServiceError.commandFailed(
                Self.bestFailureMessage(output: initial.output, exitCode: initial.exitCode)
            )
        }

        let branchResult = try await self.runWorkspaceCommand(
            host: host,
            password: password,
            workspacePath: workspacePath,
            command: "git rev-parse --abbrev-ref HEAD",
            timeoutSeconds: 20
        )
        guard branchResult.exitCode == 0 else {
            throw SSHGitServiceError.commandFailed(
                Self.bestFailureMessage(output: branchResult.output, exitCode: branchResult.exitCode)
            )
        }
        let branch = branchResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branch.isEmpty, branch != "HEAD" else {
            throw SSHGitServiceError.invalidCurrentBranch
        }

        let remote = try await self.resolveUpstreamRemote(
            host: host,
            password: password,
            workspacePath: workspacePath,
            branch: branch,
            initialPushOutput: initial.output
        )
        let fallback = try await self.runWorkspaceCommand(
            host: host,
            password: password,
            workspacePath: workspacePath,
            command: "git push --set-upstream '\(Self.escapeForSingleQuote(remote))' '\(Self.escapeForSingleQuote(branch))'",
            timeoutSeconds: 120
        )
        guard fallback.exitCode == 0 else {
            throw SSHGitServiceError.commandFailed(
                Self.bestFailureMessage(output: fallback.output, exitCode: fallback.exitCode)
            )
        }
        return GitPushResult(usedUpstreamFallback: true, output: fallback.output)
    }

    private func resolveUpstreamRemote(
        host: RemoteHost,
        password: String,
        workspacePath: String,
        branch: String,
        initialPushOutput: String
    ) async throws -> String {
        if let suggestedRemote = Self.parseSuggestedUpstreamRemote(initialPushOutput) {
            return suggestedRemote
        }

        let branchPushRemoteKey = "branch.\(branch).pushRemote"
        if let pushRemote = try await self.readGitConfigValue(
            host: host,
            password: password,
            workspacePath: workspacePath,
            key: branchPushRemoteKey
        ) {
            return pushRemote
        }

        let branchRemoteKey = "branch.\(branch).remote"
        if let branchRemote = try await self.readGitConfigValue(
            host: host,
            password: password,
            workspacePath: workspacePath,
            key: branchRemoteKey
        ) {
            return branchRemote
        }

        if let defaultPushRemote = try await self.readGitConfigValue(
            host: host,
            password: password,
            workspacePath: workspacePath,
            key: "remote.pushDefault"
        ) {
            return defaultPushRemote
        }

        let remoteListResult = try await self.runWorkspaceCommand(
            host: host,
            password: password,
            workspacePath: workspacePath,
            command: "git remote",
            timeoutSeconds: 20
        )
        guard remoteListResult.exitCode == 0 else {
            throw SSHGitServiceError.commandFailed(
                Self.bestFailureMessage(output: remoteListResult.output, exitCode: remoteListResult.exitCode)
            )
        }

        let remotes = Self.parseRemoteNames(remoteListResult.output)
        if let origin = remotes.first(where: { $0 == "origin" }) {
            return origin
        }
        if let firstRemote = remotes.first {
            return firstRemote
        }

        throw SSHGitServiceError.commandFailed(
            "No Git remote is configured. Add a remote before pushing."
        )
    }

    private func readGitConfigValue(
        host: RemoteHost,
        password: String,
        workspacePath: String,
        key: String
    ) async throws -> String? {
        let escapedKey = Self.escapeForSingleQuote(key)
        let result = try await self.runWorkspaceCommand(
            host: host,
            password: password,
            workspacePath: workspacePath,
            command: "git config --get '\(escapedKey)'",
            timeoutSeconds: 20
        )
        guard result.exitCode == 0 else {
            return nil
        }
        return Self.firstNonEmptyOutputLine(result.output)
            .flatMap { Self.normalizeRemoteNameCandidate($0) }
    }

    func generateCommitMessage(
        host: RemoteHost,
        password: String,
        workspacePath: String,
        model: String?
    ) async throws -> String {
        let modelArg: String
        let trimmedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedModel.isEmpty {
            modelArg = ""
        } else {
            modelArg = " --model '\(Self.escapeForSingleQuote(trimmedModel))'"
        }

        let promptPreamble = """
        Write a concise Git commit message for the staged changes.
        Rules:
        - Output exactly one line.
        - Use imperative mood.
        - No quotes, no markdown, no prefix.
        - Prefer 72 chars or fewer.

        Staged diff:
        """

        let maxPromptDiffCharacters = 12_000
        let noDiffMarker = "__CODEX_NO_STAGED_DIFF__"
        let heredocTag = "__CODEX_COMMIT_PROMPT_\(UUID().uuidString.replacingOccurrences(of: "-", with: "_"))__"
        let command = """
        if GIT_PAGER=cat git --no-pager diff --cached --quiet -- .; then
          echo "\(noDiffMarker)"
          exit 3
        fi
        {
        cat <<'\(heredocTag)'
        \(promptPreamble)
        \(heredocTag)
        GIT_PAGER=cat git --no-pager diff --cached --no-color --find-renames --unified=0 -- . | head -c \(maxPromptDiffCharacters)
        } | codex exec --json --ephemeral --skip-git-repo-check\(modelArg) -
        """

        let generationStartedAt = Date()
        Self.logger.debug(
            "SSHGit commit-message generation started maxPromptDiffChars=\(maxPromptDiffCharacters, privacy: .public)"
        )
        let result = try await self.runWorkspaceCommand(
            host: host,
            password: password,
            workspacePath: workspacePath,
            command: command,
            timeoutSeconds: 240
        )
        guard result.exitCode == 0 else {
            if result.output.contains(noDiffMarker) {
                throw SSHGitServiceError.noDiffAvailable
            }
            throw SSHGitServiceError.codexExecFailed(
                Self.bestFailureMessage(output: result.output, exitCode: result.exitCode)
            )
        }

        let generated = try Self.parseCodexExecCommitMessage(result.output)
        let oneLine = generated
            .split(whereSeparator: \.isNewline)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !oneLine.isEmpty else {
            throw SSHGitServiceError.codexExecNoMessage
        }
        let generationDurationMs = Int(Date().timeIntervalSince(generationStartedAt) * 1_000)
        Self.logger.debug(
            "SSHGit commit-message generation completed durationMs=\(generationDurationMs, privacy: .public) messageChars=\(oneLine.count, privacy: .public)"
        )
        return oneLine
    }

    private func resolveDiffBaseReference(
        host: RemoteHost,
        password: String,
        workspacePath: String
    ) async throws -> String {
        let headResult = try await self.runWorkspaceCommand(
            host: host,
            password: password,
            workspacePath: workspacePath,
            command: "git rev-parse --verify HEAD",
            timeoutSeconds: 20
        )

        if headResult.exitCode == 0 {
            guard let headRef = Self.firstNonEmptyOutputLine(headResult.output),
                  !headRef.isEmpty else {
                throw SSHGitServiceError.malformedOutput
            }
            return headRef
        }

        guard Self.isMissingHeadReferenceError(headResult.output) else {
            throw SSHGitServiceError.commandFailed(
                Self.bestFailureMessage(output: headResult.output, exitCode: headResult.exitCode)
            )
        }

        let emptyTreeResult = try await self.runWorkspaceCommand(
            host: host,
            password: password,
            workspacePath: workspacePath,
            command: "git hash-object -t tree /dev/null",
            timeoutSeconds: 20
        )
        guard emptyTreeResult.exitCode == 0 else {
            throw SSHGitServiceError.commandFailed(
                Self.bestFailureMessage(output: emptyTreeResult.output, exitCode: emptyTreeResult.exitCode)
            )
        }

        guard let emptyTreeRef = Self.firstNonEmptyOutputLine(emptyTreeResult.output),
              !emptyTreeRef.isEmpty else {
            throw SSHGitServiceError.malformedOutput
        }
        return emptyTreeRef
    }

    private func resolveCurrentBranchName(
        host: RemoteHost,
        password: String,
        workspacePath: String
    ) async throws -> String {
        let branchResult = try await self.runWorkspaceCommand(
            host: host,
            password: password,
            workspacePath: workspacePath,
            command: "git rev-parse --abbrev-ref HEAD",
            timeoutSeconds: 20
        )
        guard branchResult.exitCode == 0 else {
            throw SSHGitServiceError.commandFailed(
                Self.bestFailureMessage(output: branchResult.output, exitCode: branchResult.exitCode)
            )
        }
        let branchName = branchResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branchName.isEmpty else {
            return "HEAD"
        }
        return branchName
    }

    private func runWorkspaceCommand(
        host: RemoteHost,
        password: String,
        workspacePath: String,
        command: String,
        timeoutSeconds: Int
    ) async throws -> SSHGitCommandResult {
        try await withCheckedThrowingContinuation { continuation in
            let queue = DispatchQueue(label: "com.example.CodexAppMobile.ssh-git")
            queue.async {
                final class SharedState: @unchecked Sendable {
                    var fullOutput = ""
                    var completed = false
                    var sawEndMarker = false
                    var sawExitCodeMarker = false
                    var parseGraceTimerArmed = false
                    var malformedParseCount = 0
                    var parseGraceSource: DispatchSourceTimer?
                    var didConnect = false
                    var didSendCommand = false
                    var ignoredPreflightDisconnect = false
                }

                let state = SharedState()
                let commandID = String(UUID().uuidString.prefix(8))
                let engine = SSHClientEngine()
                let startMarker = "__CODEX_GIT_START__"
                let endMarker = "__CODEX_GIT_END__"
                let exitMarker = "__CODEX_GIT_EXIT__:"
                let connectTimeoutSeconds = min(20, max(5, timeoutSeconds))
                let commandLabel = Self.commandLogLabel(command)

                Self.logger.debug(
                    "SSHGit[\(commandID, privacy: .public)] start command=\(commandLabel, privacy: .public) timeout=\(timeoutSeconds, privacy: .public)s"
                )

                let timeoutSource = DispatchSource.makeTimerSource(queue: queue)
                timeoutSource.schedule(deadline: .now() + .seconds(connectTimeoutSeconds))

                let complete: @Sendable (Result<SSHGitCommandResult, Error>) -> Void = { result in
                    guard !state.completed else { return }
                    state.completed = true
                    state.parseGraceSource?.cancel()
                    state.parseGraceSource = nil
                    timeoutSource.cancel()
                    engine.disconnect()
                    switch result {
                    case .success(let parsed):
                        Self.logger.debug(
                            "SSHGit[\(commandID, privacy: .public)] completed exit=\(parsed.exitCode, privacy: .public) outputBytes=\(parsed.output.utf8.count, privacy: .public)"
                        )
                    case .failure(let error):
                        Self.logger.error(
                            "SSHGit[\(commandID, privacy: .public)] failed command=\(commandLabel, privacy: .public) error=\(String(describing: error), privacy: .public) diag=\(Self.markerDiagnosticSummary(output: state.fullOutput, startMarker: startMarker, endMarker: endMarker, exitMarker: exitMarker), privacy: .public)"
                        )
                    }
                    continuation.resume(with: result)
                }

                timeoutSource.setEventHandler {
                    guard !state.completed else { return }
                    Self.logger.error(
                        "SSHGit[\(commandID, privacy: .public)] timeout command=\(commandLabel, privacy: .public) diag=\(Self.markerDiagnosticSummary(output: state.fullOutput, startMarker: startMarker, endMarker: endMarker, exitMarker: exitMarker), privacy: .public)"
                    )
                    complete(.failure(SSHGitServiceError.timeout))
                }
                timeoutSource.resume()

                let armParseGraceTimer: @Sendable () -> Void = {
                    guard !state.parseGraceTimerArmed else { return }
                    state.parseGraceTimerArmed = true

                    let timer = DispatchSource.makeTimerSource(queue: queue)
                    timer.schedule(deadline: .now() + .seconds(3))
                    timer.setEventHandler {
                        guard !state.completed else { return }
                        complete(
                            .failure(
                                SSHGitServiceError.commandFailed(
                                    "Could not parse remote command output. See Xcode console for SSHGit diagnostics."
                                )
                            )
                        )
                    }
                    timer.resume()
                    state.parseGraceSource = timer
                    Self.logger.debug(
                        "SSHGit[\(commandID, privacy: .public)] parse-grace timer armed"
                    )
                }

                let tryParseIfPossible: @Sendable () -> Bool = {
                    do {
                        let parsed = try Self.parseCommandResult(
                            state.fullOutput,
                            startMarker: startMarker,
                            endMarker: endMarker,
                            exitMarker: exitMarker
                        )
                        complete(.success(parsed))
                        return true
                    } catch {
                        if case SSHGitServiceError.malformedOutput = error {
                            state.malformedParseCount += 1
                            if state.malformedParseCount == 1 || state.malformedParseCount % 5 == 0 {
                                Self.logger.debug(
                                    "SSHGit[\(commandID, privacy: .public)] parse pending malformed count=\(state.malformedParseCount, privacy: .public)"
                                )
                            }
                            return false
                        }
                        complete(.failure(error))
                        return false
                    }
                }

                engine.onOutput = { chunk in
                    queue.async {
                        guard !state.completed else { return }
                        state.fullOutput += chunk
                        if !state.sawEndMarker, Self.containsMarkerLine(state.fullOutput, marker: endMarker) {
                            state.sawEndMarker = true
                            Self.logger.debug(
                                "SSHGit[\(commandID, privacy: .public)] detected end marker line"
                            )
                        }
                        if !state.sawExitCodeMarker,
                           Self.containsExitCodeLine(state.fullOutput, exitMarker: exitMarker) {
                            state.sawExitCodeMarker = true
                            Self.logger.debug(
                                "SSHGit[\(commandID, privacy: .public)] detected exit marker line"
                            )
                        }
                        guard state.sawEndMarker, state.sawExitCodeMarker else {
                            return
                        }
                        if !tryParseIfPossible() {
                            armParseGraceTimer()
                        }
                    }
                }

                engine.onDisconnected = {
                    queue.async {
                        guard !state.completed else { return }
                        guard state.didConnect else {
                            if !state.ignoredPreflightDisconnect {
                                state.ignoredPreflightDisconnect = true
                                Self.logger.debug(
                                    "SSHGit[\(commandID, privacy: .public)] disconnected before connect was established; ignoring preflight disconnect"
                                )
                                return
                            }
                            complete(
                                .failure(
                                    SSHGitServiceError.commandFailed(
                                        "SSH connection closed before command connection was established. Check SSH credentials and server reachability."
                                    )
                                )
                            )
                            return
                        }
                        guard state.didSendCommand else {
                            complete(
                                .failure(
                                    SSHGitServiceError.commandFailed(
                                        "SSH session closed before command was sent. Check SSH credentials and server reachability."
                                    )
                                )
                            )
                            return
                        }
                        if state.sawEndMarker, state.sawExitCodeMarker, tryParseIfPossible() {
                            return
                        }
                        complete(
                            .failure(
                                SSHGitServiceError.commandFailed(
                                    "SSH session closed before command output was fully parsed. See Xcode console for SSHGit diagnostics."
                                )
                            )
                        )
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
                        state.didConnect = true
                        Self.logger.debug(
                            "SSHGit[\(commandID, privacy: .public)] connected"
                        )
                        timeoutSource.schedule(deadline: .now() + .seconds(timeoutSeconds))
                        let escapedPath = Self.escapeForSingleQuote(workspacePath)
                        let shellScript = "printf '%s\\n' '\(startMarker)'; (cd '\(escapedPath)' && { \(command) ; }) 2>&1; __codex_status=$?; printf '\\n\(exitMarker)%s\\n' \"$__codex_status\"; printf '%s\\n' '\(endMarker)'"
                        let wrappedCommand = "sh -lc \"\(Self.escapeForDoubleQuote(shellScript))\""
                        do {
                            try engine.send(command: wrappedCommand + "\n")
                            state.didSendCommand = true
                            Self.logger.debug(
                                "SSHGit[\(commandID, privacy: .public)] command sent"
                            )
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

    static func parseWrappedCommandResult(
        _ output: String,
        startMarker: String,
        endMarker: String,
        exitMarker: String
    ) throws -> (output: String, exitCode: Int) {
        let parsed = try self.parseCommandResult(
            output,
            startMarker: startMarker,
            endMarker: endMarker,
            exitMarker: exitMarker
        )
        return (parsed.output, parsed.exitCode)
    }

    private static func parseCommandResult(
        _ output: String,
        startMarker: String,
        endMarker: String,
        exitMarker: String
    ) throws -> SSHGitCommandResult {
        let normalized = self
            .stripANSI(output)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map(String.init)
        let startIndices = lines.indices.filter {
            lines[$0].trimmingCharacters(in: .whitespacesAndNewlines) == startMarker
        }
        let endIndices = lines.indices.filter {
            lines[$0].trimmingCharacters(in: .whitespacesAndNewlines) == endMarker
        }
        guard !startIndices.isEmpty, !endIndices.isEmpty else {
            throw SSHGitServiceError.malformedOutput
        }

        for startIndex in startIndices.reversed() {
            for endIndex in endIndices where endIndex > startIndex {
                let bodyLines = Array(lines[(startIndex + 1)..<endIndex])
                if let parsed = self.parseCommandBodyLines(bodyLines, exitMarker: exitMarker) {
                    return parsed
                }
            }
        }

        throw SSHGitServiceError.malformedOutput
    }

    private static func parseCommandBodyLines(
        _ bodyLines: [String],
        exitMarker: String
    ) -> SSHGitCommandResult? {
        var lines = bodyLines

        while lines.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            _ = lines.popLast()
        }

        guard !lines.isEmpty else {
            return nil
        }

        var exitIndex: Int?
        var exitCode: Int?
        for index in stride(from: lines.count - 1, through: 0, by: -1) {
            if let code = self.parseExitCode(from: lines[index], exitMarker: exitMarker) {
                exitIndex = index
                exitCode = code
                break
            }
        }

        guard let exitIndex, let exitCode else {
            return nil
        }

        let outputLines = Array(lines[..<exitIndex])
        let cleanOutput = outputLines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return SSHGitCommandResult(output: cleanOutput, exitCode: exitCode)
    }

    private static func parseExitCode(from line: String, exitMarker: String) -> Int? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let markerRange = trimmed.range(of: exitMarker) else {
            return nil
        }
        let suffix = trimmed[markerRange.upperBound...]
        let numberPrefix = suffix
            .drop(while: { $0.isWhitespace })
            .prefix(while: { $0.isNumber || $0 == "-" || $0 == "+" })
        guard !numberPrefix.isEmpty else {
            return nil
        }
        return Int(numberPrefix)
    }

    private static func markerRanges(of marker: String, in text: String) -> [Range<String.Index>] {
        guard !marker.isEmpty else { return [] }

        var ranges: [Range<String.Index>] = []
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let range = text.range(of: marker, range: searchStart..<text.endIndex) {
            ranges.append(range)
            searchStart = range.upperBound
        }
        return ranges
    }

    private static func containsMarkerLine(_ output: String, marker: String) -> Bool {
        self.markerLineCount(marker, in: self.stripANSI(output)) > 0
    }

    private static func containsExitCodeLine(_ output: String, exitMarker: String) -> Bool {
        guard !exitMarker.isEmpty else { return false }
        let normalized = self
            .stripANSI(output)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map(String.init)
        return lines.contains { self.parseExitCode(from: $0, exitMarker: exitMarker) != nil }
    }

    struct NumstatSummary: Equatable {
        let fileCount: Int
        let additions: Int?
        let deletions: Int?
    }

    struct PatchLineTotals: Equatable {
        let additions: Int
        let deletions: Int
        let available: Bool
    }

    static func parseNumstatSummary(_ output: String) -> NumstatSummary {
        let normalized = output.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.split(whereSeparator: \.isNewline).map(String.init)
        var fileCount = 0
        var additions = 0
        var deletions = 0
        var hasUnknownCounts = false

        for line in lines {
            let columns = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard columns.count >= 3 else { continue }
            fileCount += 1
            guard let addCount = Int(columns[0]),
                  let deleteCount = Int(columns[1]) else {
                hasUnknownCounts = true
                continue
            }
            additions += addCount
            deletions += deleteCount
        }

        if hasUnknownCounts {
            return NumstatSummary(fileCount: fileCount, additions: nil, deletions: nil)
        }
        return NumstatSummary(fileCount: fileCount, additions: additions, deletions: deletions)
    }

    static func untrackedFileCount(fromStatus output: String) -> Int {
        let normalized = output.replacingOccurrences(of: "\r\n", with: "\n")
        return normalized
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { $0.hasPrefix("?? ") }
            .count
    }

    static func isUpstreamNotSetError(_ output: String) -> Bool {
        let lowered = output.lowercased()
        return lowered.contains("no upstream branch")
            || lowered.contains("has no upstream branch")
            || lowered.contains("set-upstream")
    }

    static func parseSuggestedUpstreamRemote(_ output: String) -> String? {
        let normalized = output.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized
            .split(whereSeparator: \.isNewline)
            .map(String.init)

        for line in lines {
            if let remote = self.remoteToken(fromGitPushHintLine: line, marker: "--set-upstream") {
                return remote
            }
        }
        return nil
    }

    static func isMissingHeadReferenceError(_ output: String) -> Bool {
        let lowered = output.lowercased()
        return lowered.contains("ambiguous argument 'head'")
            || lowered.contains("bad revision 'head'")
            || lowered.contains("needed a single revision")
            || lowered.contains("unknown revision")
    }

    static func patchLineTotals(from files: [GitDiffFile]) -> PatchLineTotals {
        var additions = 0
        var deletions = 0
        var hasCountableLines = false

        for file in files {
            for hunk in file.hunks {
                for line in hunk.lines {
                    switch line.kind {
                    case .addition:
                        hasCountableLines = true
                        additions += 1
                    case .deletion:
                        hasCountableLines = true
                        deletions += 1
                    case .context, .meta:
                        break
                    }
                }
            }
        }

        return PatchLineTotals(
            additions: additions,
            deletions: deletions,
            available: hasCountableLines
        )
    }

    static func parseDiffFiles(_ patchText: String) throws -> [GitDiffFile] {
        let normalized = patchText.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map(String.init)

        var files: [MutableDiffFile] = []
        var currentFile: MutableDiffFile?
        var index = 0

        while index < lines.count {
            let line = lines[index]

            if line.hasPrefix("diff --git ") {
                if let currentFile {
                    files.append(currentFile)
                }
                currentFile = MutableDiffFile(diffHeader: line)
                index += 1
                continue
            }

            guard var file = currentFile else {
                index += 1
                continue
            }

            if line.hasPrefix("@@ ") || line.hasPrefix("@@") {
                let header = line
                var oldLine = 0
                var newLine = 0
                if let parsedHeader = self.parseHunkHeader(line) {
                    oldLine = parsedHeader.oldStart
                    newLine = parsedHeader.newStart
                }
                var hunkLines: [GitDiffLine] = []
                index += 1

                while index < lines.count {
                    let candidate = lines[index]
                    if candidate.hasPrefix("diff --git ")
                        || candidate.hasPrefix("@@ ")
                        || candidate.hasPrefix("@@") {
                        break
                    }

                    let lineID = "\(file.id)-hunk-\(file.hunks.count)-line-\(hunkLines.count)"
                    if candidate.hasPrefix("+"), !candidate.hasPrefix("+++") {
                        hunkLines.append(
                            GitDiffLine(
                                id: lineID,
                                kind: .addition,
                                oldLineNumber: nil,
                                newLineNumber: newLine,
                                text: String(candidate.dropFirst())
                            )
                        )
                        newLine += 1
                    } else if candidate.hasPrefix("-"), !candidate.hasPrefix("---") {
                        hunkLines.append(
                            GitDiffLine(
                                id: lineID,
                                kind: .deletion,
                                oldLineNumber: oldLine,
                                newLineNumber: nil,
                                text: String(candidate.dropFirst())
                            )
                        )
                        oldLine += 1
                    } else if candidate.hasPrefix(" ") {
                        hunkLines.append(
                            GitDiffLine(
                                id: lineID,
                                kind: .context,
                                oldLineNumber: oldLine,
                                newLineNumber: newLine,
                                text: String(candidate.dropFirst())
                            )
                        )
                        oldLine += 1
                        newLine += 1
                    } else {
                        hunkLines.append(
                            GitDiffLine(
                                id: lineID,
                                kind: .meta,
                                oldLineNumber: nil,
                                newLineNumber: nil,
                                text: candidate
                            )
                        )
                    }

                    index += 1
                }

                file.hunks.append(
                    GitDiffHunk(
                        id: "\(file.id)-hunk-\(file.hunks.count)",
                        header: header,
                        lines: hunkLines
                    )
                )
                currentFile = file
                continue
            }

            if line.hasPrefix("rename from ") {
                file.renameFrom = String(line.dropFirst("rename from ".count))
            } else if line.hasPrefix("rename to ") {
                file.renameTo = String(line.dropFirst("rename to ".count))
            } else if line.hasPrefix("--- ") {
                let path = String(line.dropFirst(4))
                file.oldPath = Self.normalizePatchPath(path)
            } else if line.hasPrefix("+++ ") {
                let path = String(line.dropFirst(4))
                file.newPath = Self.normalizePatchPath(path)
            } else if line.lowercased().contains("binary files") || line.hasPrefix("GIT binary patch") {
                file.isBinary = true
            }

            if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                file.metadata.append(line)
            }
            currentFile = file
            index += 1
        }

        if let currentFile {
            files.append(currentFile)
        }

        return files.map { $0.build() }
    }

    private struct MutableDiffFile {
        var id: String
        var oldPath: String?
        var newPath: String?
        var renameFrom: String?
        var renameTo: String?
        var metadata: [String] = []
        var hunks: [GitDiffHunk] = []
        var isBinary = false

        init(diffHeader: String) {
            let parsedPaths = SSHGitService.parseDiffHeaderPaths(diffHeader)
            let oldPath = parsedPaths.oldPath
            let newPath = parsedPaths.newPath
            self.oldPath = oldPath
            self.newPath = newPath
            self.id = SSHGitService.makeStableDiffFileID(
                oldPath: oldPath,
                newPath: newPath,
                diffHeader: diffHeader
            )
            self.metadata = [diffHeader]
        }

        func build() -> GitDiffFile {
            let resolvedOldPath = self.renameFrom ?? self.oldPath
            let resolvedNewPath = self.renameTo ?? self.newPath
            let fileID = SSHGitService.makeStableDiffFileID(
                oldPath: resolvedOldPath,
                newPath: resolvedNewPath,
                diffHeader: self.metadata.first ?? ""
            )
            let displayPath: String
            if let resolvedOldPath,
               let resolvedNewPath,
               resolvedOldPath != resolvedNewPath {
                displayPath = "\(resolvedOldPath) -> \(resolvedNewPath)"
            } else {
                displayPath = resolvedNewPath ?? resolvedOldPath ?? "(unknown path)"
            }
            return GitDiffFile(
                id: fileID,
                displayPath: displayPath,
                oldPath: resolvedOldPath,
                newPath: resolvedNewPath,
                metadata: self.metadata,
                hunks: self.hunks,
                isBinary: self.isBinary
            )
        }
    }

    private struct ParsedHunkHeader {
        let oldStart: Int
        let newStart: Int
    }

    private static let hunkHeaderRegex = try? NSRegularExpression(
        pattern: #"^@@ -([0-9]+)(?:,[0-9]+)? \+([0-9]+)(?:,[0-9]+)? @@"#,
        options: []
    )

    private static func parseHunkHeader(_ line: String) -> ParsedHunkHeader? {
        guard let regex = self.hunkHeaderRegex else { return nil }
        let range = NSRange(location: 0, length: line.utf16.count)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              match.numberOfRanges >= 3,
              let oldRange = Range(match.range(at: 1), in: line),
              let newRange = Range(match.range(at: 2), in: line),
              let oldStart = Int(line[oldRange]),
              let newStart = Int(line[newRange]) else {
            return nil
        }
        return ParsedHunkHeader(oldStart: oldStart, newStart: newStart)
    }

    private static func normalizePatchPath(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "/dev/null" else {
            return nil
        }
        if trimmed.hasPrefix("\""), trimmed.hasSuffix("\""), trimmed.count >= 2 {
            let start = trimmed.index(after: trimmed.startIndex)
            let end = trimmed.index(before: trimmed.endIndex)
            let unquoted = String(trimmed[start..<end])
            return self.normalizePatchPath(unquoted)
        }
        if trimmed.hasPrefix("a/") || trimmed.hasPrefix("b/") {
            return String(trimmed.dropFirst(2))
        }
        return trimmed
    }

    private static func parseDiffHeaderPaths(_ diffHeader: String) -> (oldPath: String?, newPath: String?) {
        let prefix = "diff --git "
        guard diffHeader.hasPrefix(prefix) else {
            return (nil, nil)
        }

        let body = String(diffHeader.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else {
            return (nil, nil)
        }

        guard let separator = body.range(of: " b/", options: .backwards) else {
            return (self.normalizePatchPath(body), nil)
        }

        let oldRaw = String(body[..<separator.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let newSuffix = String(body[separator.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let newRaw = "b/" + newSuffix
        return (self.normalizePatchPath(oldRaw), self.normalizePatchPath(newRaw))
    }

    private static func makeStableDiffFileID(
        oldPath: String?,
        newPath: String?,
        diffHeader: String
    ) -> String {
        let old = oldPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        let new = newPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedHeader = diffHeader.trimmingCharacters(in: .whitespacesAndNewlines)

        let base: String
        if let old, let new, old != new {
            base = "\(old)->\(new)"
        } else if let new {
            base = new
        } else if let old {
            base = old
        } else if !normalizedHeader.isEmpty {
            base = normalizedHeader
        } else {
            base = UUID().uuidString
        }

        return base
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static func remoteToken(fromGitPushHintLine line: String, marker: String) -> String? {
        guard let markerRange = line.range(of: marker) else {
            return nil
        }

        let suffix = line[markerRange.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !suffix.isEmpty else {
            return nil
        }

        guard let token = suffix.split(whereSeparator: \.isWhitespace).first else {
            return nil
        }
        return self.normalizeRemoteNameCandidate(String(token))
    }

    private static func parseRemoteNames(_ output: String) -> [String] {
        let candidates = output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .compactMap { self.normalizeRemoteNameCandidate($0) }

        var unique: [String] = []
        var seen = Set<String>()
        for remote in candidates where !seen.contains(remote) {
            unique.append(remote)
            seen.insert(remote)
        }
        return unique
    }

    private static func normalizeRemoteNameCandidate(_ raw: String) -> String? {
        var candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else {
            return nil
        }

        if candidate.hasPrefix("\""), candidate.hasSuffix("\""), candidate.count >= 2 {
            let start = candidate.index(after: candidate.startIndex)
            let end = candidate.index(before: candidate.endIndex)
            candidate = String(candidate[start..<end])
        } else if candidate.hasPrefix("'"), candidate.hasSuffix("'"), candidate.count >= 2 {
            let start = candidate.index(after: candidate.startIndex)
            let end = candidate.index(before: candidate.endIndex)
            candidate = String(candidate[start..<end])
        }

        while let last = candidate.last, ".,:;".contains(last) {
            candidate.removeLast()
        }

        guard !candidate.isEmpty,
              !candidate.contains(where: \.isWhitespace),
              !candidate.hasPrefix("-") else {
            return nil
        }
        return candidate
    }

    private static func bestFailureMessage(output: String, exitCode: Int) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return "Command failed (exit code \(exitCode))."
    }

    private static func commandLogLabel(_ command: String) -> String {
        let compact = command
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !compact.isEmpty else {
            return "(empty command)"
        }
        let maxLength = 180
        guard compact.count > maxLength else {
            return compact
        }
        return String(compact.prefix(maxLength)) + "..."
    }

    private static func markerDiagnosticSummary(
        output: String,
        startMarker: String,
        endMarker: String,
        exitMarker: String
    ) -> String {
        let cleanOutput = self.stripANSI(output)
        let startCount = self.markerLineCount(startMarker, in: cleanOutput)
        let endCount = self.markerLineCount(endMarker, in: cleanOutput)
        let exitCount = self.exitCodeLineCount(exitMarker, in: cleanOutput)
        let rawTail = String(cleanOutput.suffix(220))
        let sanitizedTail = rawTail
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\"", with: "'")
        return "bytes=\(cleanOutput.utf8.count) start=\(startCount) end=\(endCount) exit=\(exitCount) tail=\"\(sanitizedTail)\""
    }

    private static func markerLineCount(_ marker: String, in output: String) -> Int {
        guard !marker.isEmpty else { return 0 }
        let normalized = output
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return normalized
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { $0.trimmingCharacters(in: .whitespacesAndNewlines) == marker }
            .count
    }

    private static func exitCodeLineCount(_ exitMarker: String, in output: String) -> Int {
        guard !exitMarker.isEmpty else { return 0 }
        let normalized = output
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return normalized
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { self.parseExitCode(from: $0, exitMarker: exitMarker) != nil }
            .count
    }

    private static func gitNoPagerCommand(_ subcommand: String) -> String {
        "GIT_PAGER=cat git --no-pager \(subcommand)"
    }

    private static func firstNonEmptyOutputLine(_ output: String) -> String? {
        output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }

    private static func parseCodexExecCommitMessage(_ output: String) throws -> String {
        let lines = self.nonEmptyLines(from: output)
        var assistantChunks: [String] = []
        var nonJSONLines: [String] = []
        var errorLines: [String] = []

        for line in lines {
            guard line.hasPrefix("{"),
                  let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = object["type"] as? String else {
                nonJSONLines.append(line)
                continue
            }

            if type == "item.completed",
               let item = object["item"] as? [String: Any],
               let itemType = item["type"] as? String,
               itemType == "agent_message",
               let text = item["text"] as? String,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                assistantChunks.append(text)
                continue
            }

            if type == "error",
               let message = object["message"] as? String,
               !message.isEmpty {
                errorLines.append(message)
            }
        }

        if !errorLines.isEmpty && assistantChunks.isEmpty {
            throw SSHGitServiceError.codexExecFailed(errorLines.joined(separator: "\n"))
        }

        let message = assistantChunks.joined(separator: "\n")
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedMessage.isEmpty {
            return trimmedMessage
        }

        let fallback = nonJSONLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fallback.isEmpty else {
            throw SSHGitServiceError.codexExecNoMessage
        }
        return fallback
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

    private static func escapeForDoubleQuote(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "`", with: "\\`")
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
