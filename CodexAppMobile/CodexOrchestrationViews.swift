import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HostsView(
            remoteHostStore: self.appState.remoteHostStore,
            appServerClient: self.appState.appServerClient
        )
        .sheet(item: self.$appState.terminalLaunchContext) { _ in
            TerminalView()
        }
    }
}

struct HostsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var remoteHostStore: RemoteHostStore
    @ObservedObject var appServerClient: AppServerClient

    @State private var navigationPath: [UUID] = []
    @State private var editorContext: HostEditorContext?
    @State private var hostPendingDeletion: RemoteHost?
    @State private var loadingHostID: UUID?
    @State private var loadingErrorMessage = ""
    @State private var isPresentingLoadingError = false

    private var isPreparingHost: Bool {
        self.loadingHostID != nil
    }

    var body: some View {
        NavigationStack(path: self.$navigationPath) {
            Group {
                if self.remoteHostStore.hosts.isEmpty {
                    ContentUnavailableView(
                        "No Hosts",
                        systemImage: "network",
                        description: Text("Tap + to add your first host.")
                    )
                } else {
                    List {
                        ForEach(self.remoteHostStore.hosts) { host in
                            Button {
                                self.openHost(host)
                            } label: {
                                self.hostRow(host: host)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                            .contextMenu {
                                Button {
                                    self.presentHostEditor(for: host)
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }

                                Button {
                                    self.launchTerminal(for: host)
                                } label: {
                                    Label("Terminal", systemImage: "terminal")
                                }

                                Button {
                                    self.disconnectSession(for: host)
                                } label: {
                                    Label("Disconnect", systemImage: "xmark.circle")
                                }
                                .disabled(self.canDisconnectSession(for: host) == false)

                                Divider()

                                Button(role: .destructive) {
                                    self.hostPendingDeletion = host
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Hosts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        self.editorContext = HostEditorContext(host: nil, initialPassword: "")
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .disabled(self.isPreparingHost)
                    .codexActionButtonStyle()
                }
            }
            .navigationDestination(for: UUID.self) { hostID in
                if let host = self.remoteHostStore.hosts.first(where: { $0.id == hostID }) {
                    SessionWorkbenchView(host: host)
                } else {
                    ContentUnavailableView(
                        "Host Not Found",
                        systemImage: "network.slash",
                        description: Text("The selected host no longer exists.")
                    )
                }
            }
        }
        .disabled(self.isPreparingHost)
        .overlay {
            if self.isPreparingHost {
                ZStack {
                    Color.black.opacity(0.20)
                        .ignoresSafeArea()

                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.large)
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .alert("Could not load", isPresented: self.$isPresentingLoadingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(self.loadingErrorMessage)
        }
        .alert(
            "Delete this host?",
            isPresented: Binding(
                get: { self.hostPendingDeletion != nil },
                set: { isPresented in
                    if isPresented == false {
                        self.hostPendingDeletion = nil
                    }
                }
            ),
            presenting: self.hostPendingDeletion
        ) { host in
            Button("Cancel", role: .cancel) {
                self.hostPendingDeletion = nil
            }
            Button("Delete", role: .destructive) {
                self.appState.removeHost(hostID: host.id)
                self.hostPendingDeletion = nil
            }
        } message: { host in
            Text("Delete \"\(host.name)\"? This cannot be undone.")
        }
        .sheet(item: self.$editorContext) { context in
            RemoteHostEditorView(
                host: context.host,
                initialPassword: context.initialPassword
            ) { draft in
                self.remoteHostStore.upsert(hostID: context.host?.id, draft: draft)
                self.appState.cleanupSessionOrphans()
            }
        }
    }

    private func hostRow(host: RemoteHost) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(host.name)
                    .font(.headline)
                Text("\(host.username)@\(host.host):\(host.sshPort)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(host.appServerURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if self.isConnectedSession(for: host) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func presentHostEditor(for host: RemoteHost) {
        self.editorContext = HostEditorContext(
            host: host,
            initialPassword: self.remoteHostStore.password(for: host.id)
        )
    }

    private func launchTerminal(for host: RemoteHost) {
        self.appState.terminalLaunchContext = TerminalLaunchContext(
            hostID: host.id,
            projectPath: nil,
            threadID: nil,
            initialCommand: "codex"
        )
    }

    private func canDisconnectSession(for host: RemoteHost) -> Bool {
        self.isConnectedSession(for: host)
    }

    private func disconnectSession(for host: RemoteHost) {
        guard self.canDisconnectSession(for: host) else {
            return
        }
        self.appState.selectHost(host.id)
        self.appState.appServerClient.disconnect()
    }

    private func isConnectedSession(for host: RemoteHost) -> Bool {
        guard host.preferredTransport == .appServerWS,
              self.appServerClient.state == .connected
        else {
            return false
        }

        return self.normalizedEndpoint(self.appServerClient.connectedEndpoint)
            == self.normalizedEndpoint(host.appServerURL)
    }

    private func normalizedEndpoint(_ endpoint: String) -> String {
        endpoint
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
    }

    private func openHost(_ host: RemoteHost) {
        guard self.isPreparingHost == false else {
            return
        }

        self.loadingHostID = host.id
        self.loadingErrorMessage = ""

        Task { @MainActor in
            defer {
                self.loadingHostID = nil
            }

            do {
                try await self.prepareHostForNavigation(host)
                self.navigationPath.append(host.id)
            } catch {
                self.loadingErrorMessage = self.userFacingHostLoadingError(error, host: host)
                self.isPresentingLoadingError = true
            }
        }
    }

    private func prepareHostForNavigation(_ host: RemoteHost) async throws {
        self.appState.selectHost(host.id)
        self.appState.hostSessionStore.markOpened(hostID: host.id)

        guard host.preferredTransport == .appServerWS,
              self.initialWorkspace(for: host.id) != nil
        else {
            return
        }

        try await self.appState.appServerClient.connect(to: host)
        _ = try await self.appState.appServerClient.threadList(limit: 1)
    }

    private func initialWorkspace(for hostID: UUID) -> ProjectWorkspace? {
        let workspaces = self.appState.projectStore.workspaces(for: hostID)
        guard let first = workspaces.first else {
            return nil
        }

        if let selectedWorkspaceID = self.appState.hostSessionStore
            .session(for: hostID)?
            .selectedProjectID,
           let selected = workspaces.first(where: { $0.id == selectedWorkspaceID }) {
            return selected
        }

        return first
    }

    private func userFacingHostLoadingError(_ error: Error, host: RemoteHost) -> String {
        if host.preferredTransport == .appServerWS {
            return self.appState.appServerClient.userFacingMessage(for: error)
        }

        if let localized = error as? LocalizedError,
           let message = localized.errorDescription,
           !message.isEmpty {
            return message
        }

        return error.localizedDescription
    }
}

private struct HostEditorContext: Identifiable {
    let id = UUID()
    let host: RemoteHost?
    let initialPassword: String
}

struct RemoteHostEditorView: View {
    let host: RemoteHost?
    let initialPassword: String
    let onSave: (RemoteHostDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var displayName: String
    @State private var hostAddress: String
    @State private var sshPortText: String
    @State private var username: String
    @State private var appServerHost: String
    @State private var appServerPortText: String
    @State private var password: String

    init(host: RemoteHost?, initialPassword: String, onSave: @escaping (RemoteHostDraft) -> Void) {
        self.host = host
        self.initialPassword = initialPassword
        self.onSave = onSave

        let initialDraft: RemoteHostDraft
        if let host {
            initialDraft = RemoteHostDraft(host: host, password: initialPassword)
        } else {
            initialDraft = .empty
        }

        _displayName = State(initialValue: initialDraft.name)
        _hostAddress = State(initialValue: initialDraft.host)
        _sshPortText = State(initialValue: String(initialDraft.sshPort))
        _username = State(initialValue: initialDraft.username)
        _appServerHost = State(initialValue: initialDraft.appServerHost)
        _appServerPortText = State(initialValue: String(initialDraft.appServerPort))
        _password = State(initialValue: initialDraft.password)
    }

    private var parsedSSHPort: Int {
        Int(self.sshPortText) ?? 22
    }

    private var parsedAppServerPort: Int {
        Int(self.appServerPortText) ?? 8080
    }

    private var draft: RemoteHostDraft {
        RemoteHostDraft(
            name: self.displayName,
            host: self.hostAddress,
            sshPort: self.parsedSSHPort,
            username: self.username,
            appServerHost: self.appServerHost,
            appServerPort: self.parsedAppServerPort,
            preferredTransport: .appServerWS,
            password: self.password
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic") {
                    TextField("Name", text: self.$displayName)
                    TextField("Host", text: self.$hostAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    TextField("SSH Port", text: self.$sshPortText)
                        .keyboardType(.numberPad)
                    TextField("Username", text: self.$username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                }

                Section("App Server") {
                    TextField("Host (default: Basic Host)", text: self.$appServerHost)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    TextField("Port", text: self.$appServerPortText)
                        .keyboardType(.numberPad)
                }

                Section("SSH") {
                    SecureField("Password (optional)", text: self.$password)
                }
            }
            .navigationTitle(self.host == nil ? "New Host" : "Edit Host")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        self.dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Cancel")
                    .codexActionButtonStyle()
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        self.onSave(self.draft)
                        self.dismiss()
                    }
                    .disabled(!self.draft.isValid)
                    .codexActionButtonStyle()
                }
            }
        }
    }
}

private struct RemoteDirectoryEntry: Identifiable, Equatable {
    var id: String { self.path }
    let name: String
    let path: String
}

private enum RemotePathBrowserError: LocalizedError {
    case timeout
    case malformedOutput

    var errorDescription: String? {
        switch self {
        case .timeout:
            return "Directory listing timed out."
        case .malformedOutput:
            return "Could not parse remote directory output."
        }
    }
}

private actor RemotePathBrowserService {
    func listDirectories(host: RemoteHost, password: String, path: String) async throws -> (String, [RemoteDirectoryEntry]) {
        try await withCheckedThrowingContinuation { continuation in
            let queue = DispatchQueue(label: "com.example.CodexAppMobile.path-browser")
            queue.async {
                final class SharedState: @unchecked Sendable {
                    var fullOutput = ""
                    var completed = false
                }

                let state = SharedState()
                let engine = SSHClientEngine()
                let startMarker = "__CODEX_PATH_START__"
                let endMarker = "__CODEX_PATH_END__"

                let timeoutSource = DispatchSource.makeTimerSource(queue: queue)
                timeoutSource.schedule(deadline: .now() + .seconds(8))
                timeoutSource.setEventHandler {
                    guard !state.completed else { return }
                    state.completed = true
                    engine.disconnect()
                    continuation.resume(throwing: RemotePathBrowserError.timeout)
                }
                timeoutSource.resume()

                let complete: @Sendable (Result<(String, [RemoteDirectoryEntry]), Error>) -> Void = { result in
                    guard !state.completed else { return }
                    state.completed = true
                    timeoutSource.cancel()
                    engine.disconnect()
                    continuation.resume(with: result)
                }

                engine.onOutput = { chunk in
                    state.fullOutput += chunk
                    guard state.fullOutput.contains(endMarker) else { return }
                    do {
                        let parsed = try Self.parseOutput(
                            state.fullOutput,
                            startMarker: startMarker,
                            endMarker: endMarker
                        )
                        complete(.success(parsed))
                    } catch {
                        complete(.failure(error))
                    }
                }

                engine.onError = { error in
                    complete(.failure(error))
                }

                engine.onConnected = {
                    let escapedPath = Self.escapeForSingleQuote(path)
                    let command = [
                        "printf '\(startMarker)\\n';",
                        "TARGET='\(escapedPath)';",
                        "if [ -z \"$TARGET\" ] || [ \"$TARGET\" = \"~\" ]; then",
                        "cd \"$HOME\" 2>/dev/null || cd /;",
                        "elif [ \"${TARGET#~/}\" != \"$TARGET\" ]; then",
                        "cd \"$HOME/${TARGET#~/}\" 2>/dev/null || cd /;",
                        "else",
                        "cd \"$TARGET\" 2>/dev/null || cd /;",
                        "fi;",
                        "pwd;",
                        "LC_ALL=C find . -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | sed 's#^\\./##' | LC_ALL=C sort;",
                        "printf '\(endMarker)\\n'",
                    ].joined(separator: " ")
                    do {
                        try engine.send(command: command + "\n")
                    } catch {
                        complete(.failure(error))
                    }
                }

                do {
                    try engine.connect(
                        host: host.host,
                        port: host.sshPort,
                        username: host.username,
                        password: password.isEmpty ? nil : password
                    )
                } catch {
                    complete(.failure(error))
                }
            }
        }
    }

    private static func escapeForSingleQuote(_ path: String) -> String {
        path.replacingOccurrences(of: "'", with: "'\"'\"'")
    }

    private static func stripANSI(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"\u{001B}\[[0-9;?]*[ -/]*[@-~]"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func parseOutput(
        _ output: String,
        startMarker: String,
        endMarker: String
    ) throws -> (String, [RemoteDirectoryEntry]) {
        guard let startRange = output.range(of: startMarker),
              let endRange = output.range(of: endMarker),
              startRange.upperBound <= endRange.lowerBound
        else {
            throw RemotePathBrowserError.malformedOutput
        }

        let body = output[startRange.upperBound..<endRange.lowerBound]
        let lines = body
            .split(whereSeparator: \.isNewline)
            .map { Self.stripANSI(String($0)).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let currentPath = lines.first else {
            throw RemotePathBrowserError.malformedOutput
        }

        let directories = lines.dropFirst().compactMap { raw -> RemoteDirectoryEntry? in
            let normalized = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
            let name = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
            guard name != "." && name != ".." && !name.isEmpty else { return nil }
            let fullPath: String
            if name.hasPrefix("/") {
                fullPath = name
            } else {
                fullPath = currentPath == "/" ? "/\(name)" : "\(currentPath)/\(name)"
            }
            return RemoteDirectoryEntry(name: name, path: fullPath)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return (currentPath, directories)
    }
}

private struct SSHCodexExecResult {
    let threadID: String
    let assistantText: String
}

private enum SSHCodexExecError: LocalizedError {
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

private actor SSHCodexExecService {
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

                let timeoutSource = DispatchSource.makeTimerSource(queue: queue)
                timeoutSource.schedule(deadline: .now() + .seconds(timeoutSeconds))
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

                engine.onError = { error in
                    complete(.failure(error))
                }

                engine.onConnected = {
                    let wrappedCommand = "printf '\(startMarker)\\n'; \(command) 2>&1; printf '\\n\(endMarker)\\n'"
                    do {
                        try engine.send(command: wrappedCommand + "\n")
                    } catch {
                        complete(.failure(error))
                    }
                }

                do {
                    try engine.connect(
                        host: host.host,
                        port: host.sshPort,
                        username: host.username,
                        password: password.isEmpty ? nil : password
                    )
                } catch {
                    complete(.failure(error))
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

struct RemotePathBrowserView: View {
    let host: RemoteHost
    let hostPassword: String
    let initialPath: String
    let onSelectPath: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var currentPath = ""
    @State private var entries: [RemoteDirectoryEntry] = []
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var inputPath = ""
    @State private var activeLoadRequestID = 0

    private let service = RemotePathBrowserService()

    var body: some View {
        NavigationStack {
            List {
                Section("Navigate") {
                    HStack(spacing: 8) {
                        TextField("/absolute/path or ~", text: self.$inputPath)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .font(.footnote.monospaced())
                        Button("Open") {
                            self.load(path: self.inputPath)
                        }
                        .disabled(self.isLoading)
                    }

                    HStack(spacing: 10) {
                        Button {
                            self.load(path: "~")
                        } label: {
                            Label("Home", systemImage: "house")
                        }
                        .buttonStyle(.plain)
                        .disabled(self.isLoading)

                        Button {
                            self.load(path: "/")
                        } label: {
                            Label("Root", systemImage: "internaldrive")
                        }
                        .buttonStyle(.plain)
                        .disabled(self.isLoading)

                        Button {
                            self.load(path: self.currentPath.isEmpty ? self.initialPath : self.currentPath)
                        } label: {
                            Label("Reload", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.plain)
                        .disabled(self.isLoading)
                    }
                    .font(.footnote)
                }

                Section("Current") {
                    Text(self.currentPath.isEmpty ? self.initialPath : self.currentPath)
                        .font(.footnote)
                        .fontDesign(.monospaced)
                        .textSelection(.enabled)
                }

                if let parentPath = self.parentPath(of: self.currentPath) {
                    Section {
                        Button {
                            self.load(path: parentPath)
                        } label: {
                            Label("..", systemImage: "arrow.up.left")
                        }
                        .disabled(self.isLoading)
                    }
                }

                Section("Directories") {
                    if self.isLoading {
                        ProgressView("Loading...")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if self.entries.isEmpty {
                        Text(self.isLoading ? "Loading..." : "No subdirectories")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(self.entries) { entry in
                            Button {
                                self.load(path: entry.path)
                            } label: {
                                Label(entry.name, systemImage: "folder")
                            }
                            .disabled(self.isLoading)
                        }
                    }
                }

                if self.hostPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section {
                        Text("SSH password is empty. If authentication fails, set the password in host settings and retry.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !self.errorMessage.isEmpty {
                    Section {
                        Text(self.errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Remote Paths")
            .refreshable {
                self.load(path: self.currentPath.isEmpty ? self.initialPath : self.currentPath)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        self.dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                    .codexActionButtonStyle()
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Use This Path") {
                        self.onSelectPath(self.currentPath.isEmpty ? self.initialPath : self.currentPath)
                        self.dismiss()
                    }
                    .codexActionButtonStyle()
                }
            }
            .task {
                if self.inputPath.isEmpty {
                    self.inputPath = self.initialPath
                }
                if self.currentPath.isEmpty {
                    self.load(path: self.initialPath)
                }
            }
        }
    }

    private func parentPath(of path: String) -> String? {
        let cleaned = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned != "/" else { return nil }
        let url = URL(filePath: cleaned)
        let parent = url.deletingLastPathComponent().path()
        return parent.isEmpty ? "/" : parent
    }

    private func load(path: String) {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackPath = self.currentPath.isEmpty ? self.initialPath : self.currentPath
        let targetPath = trimmedPath.isEmpty ? fallbackPath : trimmedPath

        self.errorMessage = ""
        self.isLoading = true
        self.activeLoadRequestID += 1
        let requestID = self.activeLoadRequestID

        Task {
            defer {
                if requestID == self.activeLoadRequestID {
                    self.isLoading = false
                }
            }

            do {
                let (resolvedPath, directories) = try await self.service.listDirectories(
                    host: self.host,
                    password: self.hostPassword,
                    path: targetPath
                )
                guard requestID == self.activeLoadRequestID else { return }
                self.currentPath = resolvedPath
                self.entries = directories
                self.inputPath = resolvedPath
            } catch {
                guard requestID == self.activeLoadRequestID else { return }
                self.errorMessage = self.userFacingErrorMessage(for: error)
            }
        }
    }

    private func userFacingErrorMessage(for error: Error) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            return "Failed to load remote directories."
        }

        if message.localizedCaseInsensitiveContains("authentication failed") {
            return "Authentication failed. Check username/password in host settings."
        }
        if message.localizedCaseInsensitiveContains("host key changed") {
            return "Host key changed. Reconnect from Terminal and trust the new key."
        }
        return message
    }
}

struct ProjectEditorView: View {
    let workspace: ProjectWorkspace?
    let host: RemoteHost
    let hostPassword: String
    let onSave: (ProjectWorkspaceDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var remotePath: String
    @State private var defaultModel: String
    @State private var defaultApprovalPolicy: CodexApprovalPolicy
    @State private var isPresentingPathBrowser = false

    init(
        workspace: ProjectWorkspace?,
        host: RemoteHost,
        hostPassword: String,
        onSave: @escaping (ProjectWorkspaceDraft) -> Void
    ) {
        self.workspace = workspace
        self.host = host
        self.hostPassword = hostPassword
        self.onSave = onSave

        _name = State(initialValue: workspace?.name ?? "")
        _remotePath = State(initialValue: workspace?.remotePath ?? "")
        _defaultModel = State(initialValue: workspace?.defaultModel ?? "")
        _defaultApprovalPolicy = State(initialValue: workspace?.defaultApprovalPolicy ?? .onRequest)
    }

    private var draft: ProjectWorkspaceDraft {
        ProjectWorkspaceDraft(
            name: self.name,
            remotePath: self.remotePath,
            defaultModel: self.defaultModel,
            defaultApprovalPolicy: self.defaultApprovalPolicy
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic") {
                    TextField("Name (optional)", text: self.$name)
                    TextField("/absolute/remote/path", text: self.$remotePath)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)

                    Button("Browse Remote Path") {
                        self.isPresentingPathBrowser = true
                    }
                    .codexActionButtonStyle()
                }

                Section("Defaults") {
                    TextField("Model (optional)", text: self.$defaultModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)

                    Picker("Approval Policy", selection: self.$defaultApprovalPolicy) {
                        ForEach(CodexApprovalPolicy.allCases) { policy in
                            Text(policy.displayName).tag(policy)
                        }
                    }
                }
            }
            .navigationTitle(self.workspace == nil ? "New Project" : "Edit Project")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        self.dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Cancel")
                    .codexActionButtonStyle()
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        self.onSave(self.draft)
                        self.dismiss()
                    }
                    .disabled(!self.draft.isValid)
                    .codexActionButtonStyle()
                }
            }
        }
        .sheet(isPresented: self.$isPresentingPathBrowser) {
            RemotePathBrowserView(
                host: self.host,
                hostPassword: self.hostPassword,
                initialPath: self.remotePath.isEmpty ? "~" : self.remotePath
            ) { selectedPath in
                self.remotePath = selectedPath
            }
        }
    }
}

private enum SessionChatRole {
    case user
    case assistant
}

private struct SessionChatMessage: Identifiable, Equatable {
    let id: String
    let role: SessionChatRole
    let text: String
}

struct SessionWorkbenchView: View {
    private enum AssistantStreamingPhase {
        case thinking
        case responding
    }

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let host: RemoteHost

    @State private var selectedWorkspaceID: UUID?
    @State private var selectedThreadID: String?
    @State private var prompt = ""
    @State private var localErrorMessage = ""
    @State private var localStatusMessage = ""
    @State private var isRefreshingThreads = false
    @State private var isRunningSSHAction = false
    @State private var isPresentingProjectEditor = false
    @State private var editingWorkspace: ProjectWorkspace?
    @State private var workspacePendingDeletion: ProjectWorkspace?
    @State private var activePendingRequest: AppServerPendingRequest?
    @State private var sshTranscriptByThread: [String: String] = [:]
    @State private var isMenuOpen = false
    @State private var selectedComposerModel = ""
    @State private var selectedComposerReasoning = "low"
    @FocusState private var isPromptFieldFocused: Bool

    private let sshCodexExecService = SSHCodexExecService()

    private var isSSHTransport: Bool {
        self.host.preferredTransport == .ssh
    }

    private var selectedWorkspace: ProjectWorkspace? {
        guard let selectedWorkspaceID else { return nil }
        return self.workspaces.first(where: { $0.id == selectedWorkspaceID })
    }

    private var workspaces: [ProjectWorkspace] {
        self.appState.projectStore.workspaces(for: self.host.id)
    }

    private var selectedWorkspaceThreads: [CodexThreadSummary] {
        guard let selectedWorkspaceID else { return [] }
        return self.threads(for: selectedWorkspaceID)
    }

    private func threads(for workspaceID: UUID) -> [CodexThreadSummary] {
        self.appState.threadBookmarkStore
            .threads(for: workspaceID)
            .filter { !$0.archived }
    }

    private var selectedThreadSummary: CodexThreadSummary? {
        guard let selectedWorkspaceID,
              let selectedThreadID else {
            return nil
        }
        return self.threads(for: selectedWorkspaceID).first(where: { $0.threadID == selectedThreadID })
    }

    private var selectedThreadTitle: String {
        guard let summary = self.selectedThreadSummary else {
            return "New Thread"
        }
        let title = summary.preview.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "New Thread" : title
    }

    private var selectedWorkspaceTitle: String {
        self.selectedWorkspace?.displayName ?? "Project"
    }

    private var selectedThreadTranscript: String {
        guard let selectedThreadID else { return "" }
        if self.isSSHTransport {
            return self.sshTranscriptByThread[selectedThreadID] ?? ""
        }
        return self.appState.appServerClient.transcriptByThread[selectedThreadID] ?? ""
    }

    private var parsedChatMessages: [SessionChatMessage] {
        Self.parseChatMessages(from: self.selectedThreadTranscript)
    }

    private var isPromptEmpty: Bool {
        self.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSendPrompt: Bool {
        !self.isPromptEmpty
            && !self.isRunningSSHAction
            && self.selectedWorkspace != nil
    }

    private var hasVisibleAssistantReplyForLatestPrompt: Bool {
        let lastUserIndex = self.parsedChatMessages.lastIndex(where: { $0.role == .user })
        let lastAssistantIndex = self.parsedChatMessages.lastIndex { message in
            guard message.role == .assistant else { return false }
            return !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        guard let lastAssistantIndex else {
            return false
        }
        guard let lastUserIndex else {
            return true
        }
        return lastAssistantIndex > lastUserIndex
    }

    private var assistantStreamingPhase: AssistantStreamingPhase? {
        if self.hasVisibleAssistantReplyForLatestPrompt {
            return nil
        }

        if self.isSSHTransport {
            return self.isRunningSSHAction ? .responding : nil
        }

        guard let selectedThreadID else { return nil }

        if let phase = self.appState.appServerClient.turnStreamingPhase(for: selectedThreadID) {
            switch phase {
            case .thinking:
                return .thinking
            case .responding:
                return .responding
            }
        }

        return self.appState.appServerClient.activeTurnID(for: selectedThreadID) != nil
            ? .thinking
            : nil
    }

    private func assistantStreamingBaseText(for phase: AssistantStreamingPhase) -> String {
        switch phase {
        case .thinking:
            return "Thinking"
        case .responding:
            return "Generating reply"
        }
    }

    private func animatedStreamingStatus(baseText: String, date: Date) -> String {
        let step = Int(date.timeIntervalSinceReferenceDate * 2).quotientAndRemainder(dividingBy: 4).remainder
        let dots = String(repeating: ".", count: max(1, step))
        return baseText + dots
    }

    private var isComposerInteractive: Bool {
        !self.isRunningSSHAction && self.selectedWorkspace != nil
    }

    private var fallbackReasoningEffortOptions: [CodexReasoningEffortOption] {
        [
            CodexReasoningEffortOption(value: "low", description: nil),
            CodexReasoningEffortOption(value: "medium", description: nil),
            CodexReasoningEffortOption(value: "high", description: nil),
        ]
    }

    private var composerModelDescriptors: [AppServerModelDescriptor] {
        var options: [AppServerModelDescriptor] = []
        var seenModels: Set<String> = []

        if !self.isSSHTransport {
            for model in self.appState.appServerClient.availableModels {
                let trimmed = model.model.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !seenModels.contains(trimmed) else { continue }
                seenModels.insert(trimmed)
                options.append(model)
            }
        }

        func appendIfNeeded(_ rawModel: String, displayName: String? = nil, isDefault: Bool = false) {
            let trimmed = rawModel.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seenModels.contains(trimmed) else { return }
            seenModels.insert(trimmed)
            options.append(
                AppServerModelDescriptor(
                    model: trimmed,
                    displayName: displayName ?? trimmed,
                    reasoningEffortOptions: [],
                    defaultReasoningEffort: nil,
                    isDefault: isDefault
                )
            )
        }

        appendIfNeeded(self.selectedComposerModel)
        appendIfNeeded(self.selectedWorkspace?.defaultModel ?? "", isDefault: true)
        appendIfNeeded(self.appState.appServerClient.diagnostics.currentModel, isDefault: true)
        appendIfNeeded("gpt-5.3-codex", displayName: "GPT-5.3-Codex")
        appendIfNeeded("gpt-5.2-codex", displayName: "GPT-5.2-Codex")

        return options
    }

    private var composerModelForRequest: String? {
        let selected = self.selectedComposerModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !selected.isEmpty {
            return selected
        }

        let workspaceDefault = self.selectedWorkspace?.defaultModel.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !workspaceDefault.isEmpty {
            return workspaceDefault
        }

        if let defaultModel = self.composerModelDescriptors.first(where: { $0.isDefault })?.model {
            return defaultModel
        }

        let currentModel = self.appState.appServerClient.diagnostics.currentModel
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return currentModel.isEmpty ? nil : currentModel
    }

    private var selectedComposerModelDescriptor: AppServerModelDescriptor? {
        guard let selectedModel = self.composerModelForRequest else { return nil }
        return self.composerModelDescriptors.first(where: { $0.model == selectedModel })
    }

    private var composerModelDisplayName: String {
        if let selectedComposerModelDescriptor {
            return selectedComposerModelDescriptor.displayName
        }

        if let defaultModel = self.composerModelDescriptors.first(where: { $0.isDefault }) {
            return defaultModel.displayName
        }

        return "GPT-5.3-Codex"
    }

    private var composerReasoningOptions: [CodexReasoningEffortOption] {
        if let selectedComposerModelDescriptor,
           !selectedComposerModelDescriptor.reasoningEffortOptions.isEmpty {
            return selectedComposerModelDescriptor.reasoningEffortOptions
        }
        return self.fallbackReasoningEffortOptions
    }

    private var composerReasoningDisplayName: String {
        let selected = self.selectedComposerReasoning.trimmingCharacters(in: .whitespacesAndNewlines)
        if let matched = self.composerReasoningOptions.first(where: { $0.value == selected }) {
            return matched.displayName
        }
        if !selected.isEmpty {
            return CodexReasoningEffortOption(value: selected, description: nil).displayName
        }
        return self.fallbackReasoningEffortOptions.first?.displayName ?? "Low"
    }

    private var menuWidth: CGFloat {
        304
    }

    private var isDarkMode: Bool {
        self.colorScheme == .dark
    }

    private var windowSafeAreaTopInset: CGFloat {
        #if canImport(UIKit)
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let keyWindow = scenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        return keyWindow?.safeAreaInsets.top ?? 0
        #else
        return 0
        #endif
    }

    private func glassWhiteTint(light: Double, dark: Double) -> Color {
        Color.white.opacity(self.isDarkMode ? dark : light)
    }

    private func accentGlassTint(light: Double, dark: Double) -> Color {
        Color.accentColor.opacity(self.isDarkMode ? dark : light)
    }

    private var glassStrokeColor: Color {
        self.glassWhiteTint(light: 0.30, dark: 0.20)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            self.chatBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                self.chatTimeline
                self.chatComposer
            }

            if self.isMenuOpen {
                Color.black.opacity(self.isDarkMode ? 0.34 : 0.18)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        self.isPromptFieldFocused = false
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                            self.isMenuOpen = false
                        }
                    }
                    .zIndex(1)
            }

        }
        .safeAreaInset(edge: .top, spacing: 0) {
            self.chatHeader
        }
        .overlay(alignment: .leading) {
            self.sideMenu
                .zIndex(2)
        }
        .overlay(alignment: .leading) {
            if !self.isMenuOpen {
                self.menuEdgeOpenHandle
                    .zIndex(3)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.88), value: self.isMenuOpen)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            self.appState.selectHost(self.host.id)
            self.appState.hostSessionStore.markOpened(hostID: self.host.id)
            self.restoreSelectionFromSession()
            if self.selectedWorkspaceID == nil,
               let firstWorkspace = self.workspaces.first {
                self.selectedWorkspaceID = firstWorkspace.id
                self.appState.hostSessionStore.selectProject(hostID: self.host.id, projectID: firstWorkspace.id)
            }
            if self.isSSHTransport {
                self.appState.appServerClient.disconnect()
            }
            self.syncComposerControlsWithWorkspace()
            if self.selectedWorkspace != nil {
                self.refreshThreads()
            }
        }
        .onChange(of: self.selectedWorkspaceID) {
            self.syncComposerControlsWithWorkspace()
            if self.selectedWorkspace != nil {
                self.refreshThreads()
            }
        }
        .onChange(of: self.selectedComposerModel) {
            self.syncComposerReasoningWithModel()
        }
        .onChange(of: self.appState.appServerClient.availableModels) {
            self.syncComposerControlsWithWorkspace()
        }
        .alert(
            "Delete this project?",
            isPresented: Binding(
                get: { self.workspacePendingDeletion != nil },
                set: { isPresented in
                    if isPresented == false {
                        self.workspacePendingDeletion = nil
                    }
                }
            ),
            presenting: self.workspacePendingDeletion
        ) { workspace in
            Button("Cancel", role: .cancel) {
                self.workspacePendingDeletion = nil
            }
            Button("Delete", role: .destructive) {
                self.deleteWorkspace(workspace)
            }
        } message: { workspace in
            Text("Delete \"\(workspace.displayName)\"? This cannot be undone.")
        }
        .sheet(isPresented: self.$isPresentingProjectEditor) {
            ProjectEditorView(
                workspace: self.editingWorkspace,
                host: self.host,
                hostPassword: self.appState.remoteHostStore.password(for: self.host.id)
            ) { draft in
                let isCreatingWorkspace = self.editingWorkspace == nil
                let savedWorkspaceID = self.appState.projectStore.upsert(
                    workspaceID: self.editingWorkspace?.id,
                    hostID: self.host.id,
                    draft: draft
                )
                if isCreatingWorkspace {
                    self.selectedWorkspaceID = savedWorkspaceID
                    self.createNewThread()
                } else {
                    self.restoreSelectionFromSession()
                }
            }
        }
        .sheet(item: self.$activePendingRequest) { request in
            PendingRequestSheet(request: request)
                .environmentObject(self.appState)
        }
    }

    private var chatBackground: some View {
        Color.black
    }

    private var chatHeader: some View {
        HStack(spacing: 12) {
            Button {
                self.isPromptFieldFocused = false
                withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                    self.isMenuOpen.toggle()
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.white)

            VStack(alignment: .leading, spacing: 0) {
                Text(self.selectedThreadTitle)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                Text(self.selectedWorkspaceTitle)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.62))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                if let selectedThreadSummary {
                    Button(role: .destructive) {
                        self.archiveThread(summary: selectedThreadSummary, archived: true)
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                } else {
                    Text("No thread to archive")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.white)
            .disabled(self.selectedThreadSummary == nil)
            .opacity(self.selectedThreadSummary == nil ? 0.42 : 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color.black)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.14))
                .frame(height: 0.5)
        }
    }

    private var chatTimeline: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 14) {
                    if !self.localErrorMessage.isEmpty {
                        self.chatInfoBanner(
                            text: self.localErrorMessage,
                            icon: "exclamationmark.triangle.fill",
                            foreground: .red,
                            background: Color.red.opacity(0.12)
                        )
                    }

                    if !self.localStatusMessage.isEmpty {
                        self.chatInfoBanner(
                            text: self.localStatusMessage,
                            icon: "checkmark.circle",
                            foreground: Color.white.opacity(0.78),
                            background: Color.white.opacity(0.08)
                        )
                    }

                    if !self.isSSHTransport,
                       !self.appState.appServerClient.pendingRequests.isEmpty {
                        Button {
                            self.activePendingRequest = self.appState.appServerClient.pendingRequests.first
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "clock.badge.exclamationmark")
                                Text("\(self.appState.appServerClient.pendingRequests.count) approvals pending")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                            }
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    if self.selectedWorkspace == nil {
                        self.chatPlaceholder("Create or select a project.")
                    } else if self.selectedThreadID != nil && self.parsedChatMessages.isEmpty {
                        self.chatPlaceholder("No messages yet.")
                    } else if self.selectedThreadID != nil {
                        ForEach(self.parsedChatMessages) { message in
                            self.chatMessageRow(message)
                        }
                    }

                    if let assistantStreamingPhase {
                        self.chatStreamingStatusRow(baseText: self.assistantStreamingBaseText(for: assistantStreamingPhase))
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("chat-bottom")
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 18)
            }
            .background(Color.black)
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                self.scrollToBottom(proxy: proxy)
            }
            .onChange(of: self.selectedThreadTranscript) {
                self.scrollToBottom(proxy: proxy)
            }
            .onChange(of: self.selectedThreadID) {
                self.scrollToBottom(proxy: proxy)
            }
            .onChange(of: self.appState.appServerClient.activeTurnIDByThread) {
                self.scrollToBottom(proxy: proxy)
            }
            .onChange(of: self.appState.appServerClient.turnStreamingPhaseByThread) {
                self.scrollToBottom(proxy: proxy)
            }
        }
    }

    @ViewBuilder
    private func composerPickerChip(_ title: String, minWidth: CGFloat? = nil) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.72))
        }
        .foregroundStyle(Color.white.opacity(0.92))
        .padding(.horizontal, 12)
        .frame(minWidth: minWidth, minHeight: 44, maxHeight: 44, alignment: .leading)
        .background {
            self.glassCardBackground(cornerRadius: 22, tint: self.glassWhiteTint(light: 0.20, dark: 0.14))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(self.glassStrokeColor.opacity(0.56), lineWidth: 0.9)
        }
    }

    @ViewBuilder
    private var composerKeyboardDismissButton: some View {
        Button {
            self.isPromptFieldFocused = false
        } label: {
            Image(systemName: "keyboard.chevron.compact.down")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))
                .frame(width: 44, height: 44)
                .background {
                    self.glassCircleBackground(
                        size: 44,
                        tint: self.glassWhiteTint(light: 0.20, dark: 0.14)
                    )
                }
        }
        .buttonStyle(.plain)
    }

    private var composerControlBar: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(self.composerModelDescriptors) { model in
                    Button {
                        self.selectedComposerModel = model.model
                    } label: {
                        if model.model == self.composerModelForRequest {
                            Label(model.displayName, systemImage: "checkmark")
                        } else {
                            Text(model.displayName)
                        }
                    }
                }
            } label: {
                self.composerPickerChip(self.composerModelDisplayName, minWidth: 150)
            }
            .buttonStyle(.plain)
            .disabled(!self.isComposerInteractive)
            .opacity(self.isComposerInteractive ? 1 : 0.68)

            Menu {
                ForEach(self.composerReasoningOptions) { effort in
                    Button {
                        self.selectedComposerReasoning = effort.value
                    } label: {
                        if effort.value == self.selectedComposerReasoning {
                            Label(effort.displayName, systemImage: "checkmark")
                        } else {
                            Text(effort.displayName)
                        }
                    }
                }
            } label: {
                self.composerPickerChip(self.composerReasoningDisplayName, minWidth: 84)
            }
            .buttonStyle(.plain)
            .disabled(!self.isComposerInteractive)
            .opacity(self.isComposerInteractive ? 1 : 0.68)

            Spacer(minLength: 8)

            if self.isPromptFieldFocused {
                self.composerKeyboardDismissButton
            }
        }
    }

    private var chatComposer: some View {
        let isInactive = !self.isComposerInteractive

        return VStack(alignment: .leading, spacing: 8) {
            self.composerControlBar

            HStack(alignment: .bottom, spacing: 10) {
                ZStack(alignment: .leading) {
                    if self.prompt.isEmpty {
                        Image(systemName: "sparkles")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.38))
                            .allowsHitTesting(false)
                    }

                    TextField("", text: self.$prompt, axis: .vertical)
                        .lineLimit(1...4)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.send)
                        .focused(self.$isPromptFieldFocused)
                        .foregroundStyle(Color.white)
                        .tint(Color.white)
                        .frame(minHeight: 36)
                        .disabled(isInactive)
                        .opacity(isInactive ? 0.72 : 1)
                        .onSubmit {
                            if self.canSendPrompt {
                                self.sendPrompt(forceNewThread: false)
                            }
                        }
                }

                Button {
                    self.isPromptFieldFocused = false
                    self.sendPrompt(forceNewThread: false)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(isInactive ? Color.white.opacity(0.72) : Color.black)
                        .frame(width: 36, height: 36)
                        .background((isInactive ? Color.white.opacity(0.24) : Color.white), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!self.canSendPrompt)
                .opacity(self.canSendPrompt ? 1 : 0.45)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                if isInactive {
                    self.glassCardBackground(cornerRadius: 24, tint: self.glassWhiteTint(light: 0.20, dark: 0.12))
                } else {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color(red: 0.14, green: 0.14, blue: 0.16))
                }
            }
            .overlay {
                if isInactive {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(self.glassStrokeColor.opacity(0.62), lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .onTapGesture {
                guard self.isComposerInteractive, self.isPromptEmpty else { return }
                self.isPromptFieldFocused = true
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .background(Color.black)
    }

    @ViewBuilder
    private func chatInfoBanner(
        text: String,
        icon: String,
        foreground: Color,
        background: Color
    ) -> some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func chatStreamingStatusRow(baseText: String) -> some View {
        TimelineView(.periodic(from: .now, by: 0.45)) { context in
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.white.opacity(0.85))

                Text(self.animatedStreamingStatus(baseText: baseText, date: context.date))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.82))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    @ViewBuilder
    private func chatPlaceholder(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Color.white.opacity(0.62))
            .frame(maxWidth: .infinity, minHeight: 200, alignment: .center)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private func chatMessageRow(_ message: SessionChatMessage) -> some View {
        if message.role == .assistant {
            Text(self.markdownAttributedText(message.text))
                .font(.body)
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .tint(Color.blue.opacity(0.94))
        } else {
            HStack {
                Spacer(minLength: 48)
                Text(self.markdownAttributedText(message.text))
                    .font(.subheadline)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .textSelection(.enabled)
                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .frame(maxWidth: 300, alignment: .trailing)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func markdownAttributedText(_ text: String) -> AttributedString {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let hasListSyntax = normalized.range(
            of: #"(?m)^\s{0,3}([-+*]|\d+[.)])\s+"#,
            options: .regularExpression
        ) != nil
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: hasListSyntax ? .inlineOnlyPreservingWhitespace : .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        if let attributed = try? AttributedString(markdown: normalized, options: options) {
            return attributed
        }
        return AttributedString(normalized)
    }

    private var sideMenu: some View {
        GeometryReader { proxy in
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(self.host.name)
                            .font(.headline)
                            .lineLimit(1)
                        Text(self.host.appServerURL)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                            self.isMenuOpen = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 34, height: 34)
                            .background {
                                self.glassCircleBackground(size: 34)
                            }
                    }
                    .buttonStyle(.plain)
                }

                ScrollView {
                    VStack(spacing: 10) {
                        Text("Project")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 2)
                            .padding(.top, 2)

                        if self.workspaces.isEmpty {
                            Text("No projects.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 14)
                                .background {
                                    self.glassCardBackground(cornerRadius: 14)
                                }
                        } else {
                            Menu {
                                ForEach(self.workspaces) { workspace in
                                    Button {
                                        self.isPromptFieldFocused = false
                                        self.selectWorkspace(workspace)
                                    } label: {
                                        if workspace.id == self.selectedWorkspaceID {
                                            Label(workspace.displayName, systemImage: "checkmark")
                                        } else {
                                            Text(workspace.displayName)
                                        }
                                    }
                                }

                                Divider()

                                Button {
                                    self.editingWorkspace = nil
                                    self.isPresentingProjectEditor = true
                                    self.isMenuOpen = false
                                } label: {
                                    Label("Add Project", systemImage: "plus")
                                }

                                if let selectedWorkspace {
                                    Button(role: .destructive) {
                                        self.workspacePendingDeletion = selectedWorkspace
                                        self.isMenuOpen = false
                                    } label: {
                                        Label("Delete Project", systemImage: "trash")
                                    }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Text(self.selectedWorkspace?.displayName ?? "Select project")
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background {
                                    self.glassCardBackground(
                                        cornerRadius: 14,
                                        tint: self.accentGlassTint(light: 0.18, dark: 0.14)
                                    )
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        Text("Threads")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 2)
                            .padding(.top, 4)

                        Button {
                            self.isPromptFieldFocused = false
                            self.createNewThread()
                            self.isMenuOpen = false
                        } label: {
                            Label("New Thread", systemImage: "plus.bubble")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background {
                                    self.glassCardBackground(cornerRadius: 14, tint: self.accentGlassTint(light: 0.16, dark: 0.12))
                                }
                        }
                        .buttonStyle(.plain)
                        .disabled(self.selectedWorkspace == nil || self.isRunningSSHAction)
                        .opacity(self.selectedWorkspace == nil ? 0.5 : 1)

                        if self.selectedWorkspace == nil {
                            Text("Select a project.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                        } else if self.selectedWorkspaceThreads.isEmpty {
                            Text("No threads")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                        } else {
                            VStack(spacing: 6) {
                                ForEach(self.selectedWorkspaceThreads) { summary in
                                    Button {
                                        if let selectedWorkspaceID {
                                            self.selectThread(summary, workspaceID: selectedWorkspaceID)
                                        }
                                    } label: {
                                        HStack(spacing: 8) {
                                            Text(summary.preview.isEmpty ? "New Thread" : summary.preview)
                                                .font(.subheadline.weight(self.selectedThreadID == summary.threadID ? .semibold : .regular))
                                                .lineLimit(1)
                                            Spacer(minLength: 8)
                                        }
                                        .foregroundStyle(
                                            self.selectedThreadID == summary.threadID
                                            ? Color.accentColor
                                            : Color.primary
                                        )
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background {
                                            if self.selectedThreadID == summary.threadID {
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .fill(Color.accentColor.opacity(self.isDarkMode ? 0.18 : 0.12))
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }

                VStack(spacing: 8) {
                    Button {
                        self.isMenuOpen = false
                        self.openInTerminal()
                    } label: {
                        Label("Terminal", systemImage: "terminal")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background {
                                self.glassCardBackground(cornerRadius: 12)
                            }
                    }
                    .buttonStyle(.plain)

                    Button {
                        self.isMenuOpen = false
                        self.dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.left")
                            Text("Back to hosts")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background {
                            self.glassCardBackground(cornerRadius: 14)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, max(proxy.safeAreaInsets.top, self.windowSafeAreaTopInset) + 12)
            .padding(.bottom, proxy.safeAreaInsets.bottom + 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: self.menuWidth)
        .background(Color(.systemBackground))
        .ignoresSafeArea(.container, edges: .vertical)
        .offset(x: self.isMenuOpen ? 0 : -(self.menuWidth + 20))
        .shadow(color: .black.opacity(self.isMenuOpen ? 0.14 : 0), radius: 16, x: 0, y: 10)
        .gesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    guard value.translation.width < -48 else { return }
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                        self.isMenuOpen = false
                    }
                }
        )
    }

    private var menuEdgeOpenHandle: some View {
        Color.clear
            .frame(width: 22)
            .contentShape(Rectangle())
            .ignoresSafeArea(.container, edges: .vertical)
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onEnded { value in
                        guard value.startLocation.x < 28,
                              value.translation.width > 52 else {
                            return
                        }
                        self.isPromptFieldFocused = false
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                            self.isMenuOpen = true
                        }
                    }
            )
    }

    @ViewBuilder
    private func glassCardBackground(cornerRadius: CGFloat, tint: Color? = nil) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let resolvedTint = tint ?? self.glassWhiteTint(light: 0.18, dark: 0.10)
        if #available(iOS 26.0, *) {
            shape
                .fill(resolvedTint)
                .glassEffect(.regular, in: shape)
        } else {
            shape
                .fill(.ultraThinMaterial)
                .overlay(
                    shape.strokeBorder(self.glassStrokeColor, lineWidth: 0.8)
                )
        }
    }

    @ViewBuilder
    private func glassCircleBackground(size: CGFloat, tint: Color? = nil) -> some View {
        let circle = Circle()
        let resolvedTint = tint ?? self.glassWhiteTint(light: 0.20, dark: 0.12)
        if #available(iOS 26.0, *) {
            circle
                .fill(resolvedTint)
                .glassEffect(.regular, in: circle)
                .frame(width: size, height: size)
        } else {
            circle
                .fill(.ultraThinMaterial)
                .overlay(
                    circle.strokeBorder(self.glassStrokeColor, lineWidth: 0.8)
                )
                .frame(width: size, height: size)
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo("chat-bottom", anchor: .bottom)
            }
        }
    }

    private func selectWorkspace(_ workspace: ProjectWorkspace) {
        let previousWorkspaceID = self.selectedWorkspaceID
        self.selectedWorkspaceID = workspace.id
        if previousWorkspaceID != workspace.id {
            self.selectedThreadID = nil
            self.appState.hostSessionStore.selectThread(hostID: self.host.id, threadID: nil)
        }
        self.appState.hostSessionStore.selectProject(hostID: self.host.id, projectID: workspace.id)
        self.refreshThreads()
    }

    private func selectThread(_ summary: CodexThreadSummary, workspaceID: UUID) {
        self.selectedWorkspaceID = workspaceID
        self.selectedThreadID = summary.threadID
        self.appState.hostSessionStore.selectProject(hostID: self.host.id, projectID: workspaceID)
        self.appState.hostSessionStore.selectThread(hostID: self.host.id, threadID: summary.threadID)
        self.applyComposerSelection(model: summary.model, reasoningEffort: summary.reasoningEffort)
        self.loadThread(summary.threadID)
        self.isMenuOpen = false
    }

    private func createNewThread() {
        self.localErrorMessage = ""
        self.localStatusMessage = ""

        guard let selectedWorkspace else {
            self.localErrorMessage = "Select a project first."
            return
        }

        self.appState.hostSessionStore.selectProject(hostID: self.host.id, projectID: selectedWorkspace.id)
        self.selectedThreadID = nil
        self.appState.hostSessionStore.selectThread(hostID: self.host.id, threadID: nil)
        self.localStatusMessage = "Ready for a new thread. Send a prompt to start."
    }

    private func deleteWorkspace(_ workspace: ProjectWorkspace) {
        let replacementWorkspaceID = self.workspaces
            .filter { $0.id != workspace.id }
            .map(\.id)
            .first

        self.appState.removeWorkspace(
            hostID: self.host.id,
            workspaceID: workspace.id,
            replacementWorkspaceID: replacementWorkspaceID
        )

        if self.selectedWorkspaceID == workspace.id {
            self.selectedWorkspaceID = replacementWorkspaceID
            self.selectedThreadID = nil
        }

        self.workspacePendingDeletion = nil
        self.localErrorMessage = ""
        self.localStatusMessage = "Project deleted."
    }

    private func syncComposerControlsWithWorkspace() {
        let selectedModel = self.selectedComposerModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !selectedModel.isEmpty {
            self.syncComposerReasoningWithModel()
            return
        }

        let workspaceDefault = self.selectedWorkspace?.defaultModel
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !workspaceDefault.isEmpty {
            self.selectedComposerModel = workspaceDefault
        } else if let defaultModel = self.appState.appServerClient.availableModels.first(where: { $0.isDefault })?.model {
            self.selectedComposerModel = defaultModel
        } else {
            let currentModel = self.appState.appServerClient.diagnostics.currentModel
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !currentModel.isEmpty {
                self.selectedComposerModel = currentModel
            }
        }

        self.syncComposerReasoningWithModel()
    }

    private func syncComposerReasoningWithModel() {
        let normalizedCurrent = self.selectedComposerReasoning.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let options = self.composerReasoningOptions
        guard !options.isEmpty else { return }

        if options.contains(where: { $0.value == normalizedCurrent }) {
            self.selectedComposerReasoning = normalizedCurrent
            return
        }

        if let defaultEffort = self.selectedComposerModelDescriptor?.defaultReasoningEffort,
           options.contains(where: { $0.value == defaultEffort }) {
            self.selectedComposerReasoning = defaultEffort
            return
        }

        self.selectedComposerReasoning = options[0].value
    }

    private func applyComposerSelection(model: String?, reasoningEffort: String?) {
        let normalizedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedReasoning = reasoningEffort?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard (normalizedModel?.isEmpty == false) || (normalizedReasoning?.isEmpty == false) else {
            return
        }

        if let normalizedModel,
           !normalizedModel.isEmpty {
            self.selectedComposerModel = normalizedModel
        }

        if let normalizedReasoning,
           !normalizedReasoning.isEmpty {
            self.selectedComposerReasoning = normalizedReasoning
        }

        self.syncComposerReasoningWithModel()
    }

    private func updateThreadBookmarkSettings(threadID: String, model: String?, reasoningEffort: String?) {
        guard let selectedWorkspaceID else { return }
        guard var summary = self.appState.threadBookmarkStore
            .threads(for: selectedWorkspaceID)
            .first(where: { $0.threadID == threadID }) else {
            return
        }

        var didChange = false

        if let normalizedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines),
           !normalizedModel.isEmpty,
           summary.model != normalizedModel {
            summary.model = normalizedModel
            didChange = true
        }

        if let normalizedReasoning = reasoningEffort?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !normalizedReasoning.isEmpty,
           summary.reasoningEffort != normalizedReasoning {
            summary.reasoningEffort = normalizedReasoning
            didChange = true
        }

        if didChange {
            self.appState.threadBookmarkStore.upsert(summary: summary)
        }
    }

    private static func parseChatMessages(from transcript: String) -> [SessionChatMessage] {
        let normalized = transcript.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var messages: [SessionChatMessage] = []
        var currentRole: SessionChatRole?
        var buffer: [String] = []

        func flushCurrent() {
            guard let currentRole else { return }
            let text = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            messages.append(
                SessionChatMessage(
                    id: "msg-\(messages.count)",
                    role: currentRole,
                    text: text
                )
            )
        }

        for line in lines {
            if line.hasPrefix("=== Turn ") {
                flushCurrent()
                currentRole = nil
                buffer = []
                continue
            }

            if line.hasPrefix("User: ") {
                flushCurrent()
                currentRole = .user
                buffer = [String(line.dropFirst("User: ".count))]
                continue
            }

            if line.hasPrefix("Assistant: ") {
                flushCurrent()
                currentRole = .assistant
                buffer = [String(line.dropFirst("Assistant: ".count))]
                continue
            }

            if line.hasPrefix("Plan: ")
                || line.hasPrefix("Reasoning: ")
                || line.hasPrefix("$ ")
                || line.hasPrefix("File change ")
                || line.hasPrefix("Item: ") {
                flushCurrent()
                currentRole = nil
                buffer = []
                continue
            }

            if line.isEmpty {
                if currentRole != nil && !buffer.isEmpty {
                    buffer.append("")
                }
                continue
            }

            if currentRole != nil {
                buffer.append(line)
            }
        }

        flushCurrent()
        return messages
    }

    private func restoreSelectionFromSession() {
        let session = self.appState.hostSessionStore.session(for: self.host.id)
        let workspaceIDs = Set(self.workspaces.map(\.id))

        if let selectedProjectID = session?.selectedProjectID,
           workspaceIDs.contains(selectedProjectID) {
            self.selectedWorkspaceID = selectedProjectID
        } else {
            self.selectedWorkspaceID = self.workspaces.first?.id
            self.appState.hostSessionStore.selectProject(hostID: self.host.id, projectID: self.selectedWorkspaceID)
        }

        if let selectedThreadID = session?.selectedThreadID,
           !selectedThreadID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.selectedThreadID = selectedThreadID
        } else {
            self.selectedThreadID = nil
        }
    }

    private func connectHost() {
        self.localErrorMessage = ""
        self.localStatusMessage = ""

        if self.isSSHTransport {
            self.isRunningSSHAction = true
            let password = self.appState.remoteHostStore.password(for: self.host.id)
            Task {
                defer {
                    self.isRunningSSHAction = false
                }
                do {
                    let version = try await self.sshCodexExecService.checkCodexVersion(host: self.host, password: password)
                    self.localStatusMessage = "SSH ready (\(version))."
                } catch {
                    self.localErrorMessage = self.userFacingSSHError(error)
                }
            }
            return
        }

        Task {
            do {
                try await self.appState.appServerClient.connect(to: self.host)
                self.localStatusMessage = "Connected to app-server."
            } catch {
                self.localErrorMessage = self.appState.appServerClient.userFacingMessage(for: error)
            }
        }
    }

    private func disconnectHost() {
        if self.isSSHTransport {
            return
        }
        self.appState.appServerClient.disconnect()
    }

    private func refreshThreads() {
        guard let selectedWorkspace else {
            self.localErrorMessage = "Select a project first."
            return
        }

        self.localErrorMessage = ""
        self.localStatusMessage = ""
        self.isRefreshingThreads = true

        Task {
            defer {
                self.isRefreshingThreads = false
            }

            if self.isSSHTransport {
                let localThreads = self.appState.threadBookmarkStore
                    .threads(for: selectedWorkspace.id)
                    .filter { !$0.archived }
                if let selectedThreadID,
                   localThreads.contains(where: { $0.threadID == selectedThreadID }) {
                    // Keep current selection.
                } else if self.selectedThreadID != nil {
                    self.selectedThreadID = nil
                    self.appState.hostSessionStore.selectThread(hostID: self.host.id, threadID: nil)
                }
                return
            }

            do {
                if self.appState.appServerClient.state != .connected {
                    try await self.appState.appServerClient.connect(to: self.host)
                }

                let fetched = try await self.appState.appServerClient.threadList(archived: false, limit: 300)
                let scoped = fetched.filter { $0.cwd == selectedWorkspace.remotePath }
                let existingByThreadID = Dictionary(
                    uniqueKeysWithValues: self.appState.threadBookmarkStore
                        .threads(for: selectedWorkspace.id)
                        .map { ($0.threadID, $0) }
                )
                let summaries: [CodexThreadSummary] = scoped.map { thread in
                    let existing = existingByThreadID[thread.id]
                    return CodexThreadSummary(
                        threadID: thread.id,
                        hostID: self.host.id,
                        workspaceID: selectedWorkspace.id,
                        preview: thread.preview,
                        updatedAt: thread.updatedAt,
                        archived: thread.archived,
                        cwd: thread.cwd,
                        model: thread.model ?? existing?.model,
                        reasoningEffort: thread.reasoningEffort ?? existing?.reasoningEffort
                    )
                }

                self.appState.threadBookmarkStore.replaceThreads(
                    for: selectedWorkspace.id,
                    hostID: self.host.id,
                    with: summaries
                )

                let selectedWorkspaceThreads = self.threads(for: selectedWorkspace.id)
                if let selectedThreadID = self.selectedThreadID,
                   selectedWorkspaceThreads.contains(where: { $0.threadID == selectedThreadID }) {
                    self.loadThread(selectedThreadID)
                } else if self.selectedThreadID != nil {
                    self.selectedThreadID = nil
                    self.appState.hostSessionStore.selectThread(hostID: self.host.id, threadID: nil)
                }
            } catch {
                self.localErrorMessage = self.appState.appServerClient.userFacingMessage(for: error)
            }
        }
    }

    private func sendPrompt(forceNewThread: Bool) {
        let trimmedPrompt = self.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return }
        guard let selectedWorkspace else {
            self.localErrorMessage = "Select a project first."
            return
        }

        self.localErrorMessage = ""
        self.localStatusMessage = ""

        if self.isSSHTransport {
            self.sendPromptViaSSH(
                prompt: trimmedPrompt,
                selectedWorkspace: selectedWorkspace,
                forceNewThread: forceNewThread
            )
            return
        }

        Task {
            do {
                if self.appState.appServerClient.state != .connected {
                    try await self.appState.appServerClient.connect(to: self.host)
                }

                var threadID = forceNewThread ? nil : self.selectedThreadID
                if threadID == nil {
                    threadID = try await self.appState.appServerClient.threadStart(
                        cwd: selectedWorkspace.remotePath,
                        approvalPolicy: selectedWorkspace.defaultApprovalPolicy,
                        model: self.composerModelForRequest
                    )
                }

                guard let threadID else {
                    self.localErrorMessage = "Failed to resolve thread."
                    return
                }

                self.selectedThreadID = threadID
                self.appState.hostSessionStore.selectThread(hostID: self.host.id, threadID: threadID)

                self.appState.appServerClient.appendLocalEcho(trimmedPrompt, to: threadID)
                var selectedModelForThread = self.selectedThreadSummary?.model
                var selectedReasoningForThread = self.selectedThreadSummary?.reasoningEffort
                if let activeTurnID = self.appState.appServerClient.activeTurnID(for: threadID) {
                    try await self.appState.appServerClient.turnSteer(
                        threadID: threadID,
                        expectedTurnID: activeTurnID,
                        inputText: trimmedPrompt
                    )
                } else {
                    _ = try await self.appState.appServerClient.turnStart(
                        threadID: threadID,
                        inputText: trimmedPrompt,
                        model: self.composerModelForRequest,
                        effort: self.selectedComposerReasoning
                    )
                    selectedModelForThread = self.composerModelForRequest
                    selectedReasoningForThread = self.selectedComposerReasoning
                }

                self.appState.threadBookmarkStore.upsert(
                    summary: CodexThreadSummary(
                        threadID: threadID,
                        hostID: self.host.id,
                        workspaceID: selectedWorkspace.id,
                        preview: trimmedPrompt,
                        updatedAt: Date(),
                        archived: false,
                        cwd: selectedWorkspace.remotePath,
                        model: selectedModelForThread,
                        reasoningEffort: selectedReasoningForThread
                    )
                )

                self.prompt = ""
            } catch {
                self.localErrorMessage = self.appState.appServerClient.userFacingMessage(for: error)
            }
        }
    }

    private func sendPromptViaSSH(
        prompt: String,
        selectedWorkspace: ProjectWorkspace,
        forceNewThread: Bool
    ) {
        let password = self.appState.remoteHostStore.password(for: self.host.id)
        let resumeThreadID = forceNewThread ? nil : self.selectedThreadID
        self.isRunningSSHAction = true

        Task {
            defer {
                self.isRunningSSHAction = false
            }

            do {
                let result = try await self.sshCodexExecService.executePrompt(
                    host: self.host,
                    password: password,
                    workspacePath: selectedWorkspace.remotePath,
                    prompt: prompt,
                    resumeThreadID: resumeThreadID,
                    forceNewThread: forceNewThread,
                    model: self.composerModelForRequest
                )

                self.selectedThreadID = result.threadID
                self.appState.hostSessionStore.selectThread(hostID: self.host.id, threadID: result.threadID)
                self.appendSSHTranscript(prompt: prompt, response: result.assistantText, threadID: result.threadID)

                self.appState.threadBookmarkStore.upsert(
                    summary: CodexThreadSummary(
                        threadID: result.threadID,
                        hostID: self.host.id,
                        workspaceID: selectedWorkspace.id,
                        preview: prompt,
                        updatedAt: Date(),
                        archived: false,
                        cwd: selectedWorkspace.remotePath
                    )
                )

                self.prompt = ""
                self.localStatusMessage = "Executed via codex exec over SSH."
            } catch {
                self.localErrorMessage = self.userFacingSSHError(error)
            }
        }
    }

    private func appendSSHTranscript(prompt: String, response: String, threadID: String) {
        var existing = self.sshTranscriptByThread[threadID] ?? ""
        if !existing.isEmpty {
            existing += "\n"
        }
        existing += "User: \(prompt)\nAssistant: \(response)"
        self.sshTranscriptByThread[threadID] = existing
    }

    private func userFacingSSHError(_ error: Error) -> String {
        if let codexError = error as? SSHCodexExecError,
           let description = codexError.errorDescription,
           !description.isEmpty {
            return "[SSH] \(description)"
        }
        let endpoint = HostKeyStore.endpointKey(host: self.host.host, port: self.host.sshPort)
        return SSHConnectionErrorFormatter.message(for: error, endpoint: endpoint)
    }

    private func loadThread(_ threadID: String) {
        if self.isSSHTransport {
            return
        }
        Task {
            do {
                let detail: CodexThreadDetail
                do {
                    detail = try await self.appState.appServerClient.threadResume(threadID: threadID)
                } catch {
                    detail = try await self.appState.appServerClient.threadRead(threadID: threadID)
                }

                let latestTurnModel = detail.turns.compactMap(\.model).last
                let latestTurnReasoning = detail.turns.compactMap(\.reasoningEffort).last
                let selectedSummary = self.selectedThreadSummary
                let resolvedModel = detail.model ?? latestTurnModel ?? selectedSummary?.model
                let resolvedReasoning = detail.reasoningEffort ?? latestTurnReasoning ?? selectedSummary?.reasoningEffort

                self.applyComposerSelection(model: resolvedModel, reasoningEffort: resolvedReasoning)
                self.updateThreadBookmarkSettings(
                    threadID: threadID,
                    model: resolvedModel,
                    reasoningEffort: resolvedReasoning
                )
            } catch {
                self.localErrorMessage = self.appState.appServerClient.userFacingMessage(for: error)
            }
        }
    }

    private func interruptActiveTurn() {
        if self.isSSHTransport {
            self.localErrorMessage = "Interrupt is only available in App Server mode."
            return
        }

        guard let threadID = self.selectedThreadID,
              let turnID = self.appState.appServerClient.activeTurnID(for: threadID) else {
            self.localErrorMessage = "No active turn to interrupt."
            return
        }

        Task {
            do {
                try await self.appState.appServerClient.turnInterrupt(threadID: threadID, turnID: turnID)
            } catch {
                self.localErrorMessage = self.appState.appServerClient.userFacingMessage(for: error)
            }
        }
    }

    private func archiveThread(summary: CodexThreadSummary, archived: Bool) {
        if self.isSSHTransport {
            var updated = summary
            updated.archived = archived
            updated.updatedAt = Date()
            self.appState.threadBookmarkStore.upsert(summary: updated)
            if archived,
               self.selectedThreadID == summary.threadID {
                self.selectedThreadID = nil
                self.appState.hostSessionStore.selectThread(hostID: self.host.id, threadID: nil)
            }
            return
        }

        Task {
            do {
                if self.appState.appServerClient.state != .connected {
                    try await self.appState.appServerClient.connect(to: self.host)
                }
                try await self.appState.appServerClient.threadArchive(threadID: summary.threadID, archived: archived)
                self.refreshThreads()
            } catch {
                self.localErrorMessage = self.appState.appServerClient.userFacingMessage(for: error)
            }
        }
    }

    private func openInTerminal() {
        let initialCommand: String
        if let selectedWorkspace,
           let selectedThreadID,
           !selectedThreadID.isEmpty {
            let escaped = selectedWorkspace.remotePath.replacingOccurrences(of: "'", with: "'\"'\"'")
            initialCommand = "cd '\(escaped)' && codex resume \(selectedThreadID)"
        } else if let selectedWorkspace {
            let escaped = selectedWorkspace.remotePath.replacingOccurrences(of: "'", with: "'\"'\"'")
            initialCommand = "cd '\(escaped)' && codex"
        } else {
            initialCommand = "codex"
        }

        self.appState.terminalLaunchContext = TerminalLaunchContext(
            hostID: self.host.id,
            projectPath: self.selectedWorkspace?.remotePath,
            threadID: self.selectedThreadID,
            initialCommand: initialCommand
        )
    }
}

struct HostDiagnosticsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var errorMessage = ""

    private var diagnostics: AppServerDiagnostics {
        self.appState.appServerClient.diagnostics
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Host") {
                    Text("State: \(self.appState.appServerClient.state.rawValue)")
                    if !self.appState.appServerClient.connectedEndpoint.isEmpty {
                        Text(self.appState.appServerClient.connectedEndpoint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                Section("Codex CLI") {
                    Text("CLI version: \(self.diagnostics.cliVersion.isEmpty ? "unknown" : self.diagnostics.cliVersion)")
                    Text("Required >= \(self.diagnostics.minimumRequiredVersion)")
                    Text("Auth status: \(self.diagnostics.authStatus)")
                    Text("Current model: \(self.diagnostics.currentModel.isEmpty ? "unknown" : self.diagnostics.currentModel)")
                }

                Section("Health") {
                    if let latency = self.diagnostics.lastPingLatencyMS {
                        Text("Ping latency: \(latency.formatted(.number.precision(.fractionLength(0)))) ms")
                    } else {
                        Text("Ping latency: unknown")
                    }
                }

                if !self.errorMessage.isEmpty {
                    Section {
                        Text(self.errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Diagnostics")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        self.dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                    .codexActionButtonStyle()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Run") {
                        self.runDiagnostics()
                    }
                    .disabled(self.appState.appServerClient.state != .connected)
                    .codexActionButtonStyle()
                }
            }
        }
    }

    private func runDiagnostics() {
        self.errorMessage = ""
        Task {
            do {
                _ = try await self.appState.appServerClient.runDiagnostics()
            } catch {
                self.errorMessage = self.appState.appServerClient.userFacingMessage(for: error)
            }
        }
    }
}
struct PendingRequestSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let request: AppServerPendingRequest

    @State private var freeFormAnswers: [String: String] = [:]
    @State private var submitError = ""

    init(request: AppServerPendingRequest) {
        self.request = request

        var defaults: [String: String] = [:]
        if case .userInput(let questions) = request.kind {
            for question in questions {
                defaults[question.id] = question.options.first?.label ?? ""
            }
        }
        _freeFormAnswers = State(initialValue: defaults)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Method") {
                    Text(self.request.method)
                        .font(.footnote)
                        .textSelection(.enabled)
                    if !self.request.threadID.isEmpty {
                        Text("thread: \(self.request.threadID)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !self.request.turnID.isEmpty {
                        Text("turn: \(self.request.turnID)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                switch self.request.kind {
                case .commandApproval(let command, let cwd, let reason):
                    Section("Command") {
                        Text(command.isEmpty ? "(empty command)" : command)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)

                        if let cwd,
                           !cwd.isEmpty {
                            Text("cwd: \(cwd)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let reason,
                           !reason.isEmpty {
                            Text(reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("Decision") {
                        ForEach(AppServerCommandApprovalDecision.allCases) { decision in
                            Button(decision.rawValue) {
                                self.respondCommand(decision)
                            }
                        }
                    }

                case .fileChange(let reason):
                    Section("File Change") {
                        if let reason,
                           !reason.isEmpty {
                            Text(reason)
                                .font(.footnote)
                        } else {
                            Text("Codex requests file-change approval.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("Decision") {
                        ForEach(AppServerFileApprovalDecision.allCases) { decision in
                            Button(decision.rawValue) {
                                self.respondFileChange(decision)
                            }
                        }
                    }

                case .userInput(let questions):
                    ForEach(questions) { question in
                        Section(question.prompt) {
                            if !question.options.isEmpty {
                                ForEach(question.options.indices, id: \.self) { index in
                                    let option = question.options[index]
                                    Button {
                                        self.freeFormAnswers[question.id] = option.label
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(option.label)
                                            if !option.description.isEmpty {
                                                Text(option.description)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                            }

                            TextField("Answer", text: Binding(
                                get: { self.freeFormAnswers[question.id] ?? "" },
                                set: { self.freeFormAnswers[question.id] = $0 }
                            ))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                        }
                    }

                    Section {
                        Button("Submit") {
                            self.respondUserInput(questions: questions)
                        }
                    }

                case .unknown:
                    Section {
                        Text("This request type is not yet mapped. Reply from desktop fallback if needed.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if !self.submitError.isEmpty {
                    Section {
                        Text(self.submitError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(self.request.title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        self.dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                    .codexActionButtonStyle()
                }
            }
        }
    }

    private func respondCommand(_ decision: AppServerCommandApprovalDecision) {
        self.submitError = ""
        Task {
            do {
                try await self.appState.appServerClient.respondCommandApproval(request: self.request, decision: decision)
                self.dismiss()
            } catch {
                self.submitError = self.appState.appServerClient.userFacingMessage(for: error)
            }
        }
    }

    private func respondFileChange(_ decision: AppServerFileApprovalDecision) {
        self.submitError = ""
        Task {
            do {
                try await self.appState.appServerClient.respondFileChangeApproval(request: self.request, decision: decision)
                self.dismiss()
            } catch {
                self.submitError = self.appState.appServerClient.userFacingMessage(for: error)
            }
        }
    }

    private func respondUserInput(questions: [AppServerUserInputQuestion]) {
        self.submitError = ""

        var answers: [String: [String]] = [:]
        for question in questions {
            let raw = self.freeFormAnswers[question.id, default: ""]
            let values = raw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            if values.isEmpty,
               let firstOption = question.options.first?.label {
                answers[question.id] = [firstOption]
            } else {
                answers[question.id] = values
            }
        }

        Task {
            do {
                try await self.appState.appServerClient.respondUserInput(request: self.request, answers: answers)
                self.dismiss()
            } catch {
                self.submitError = self.appState.appServerClient.userFacingMessage(for: error)
            }
        }
    }
}
