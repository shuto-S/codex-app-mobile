import Foundation
import SwiftUI
import Textual
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

enum CommandPaletteRow: Identifiable, Equatable {
    case command(AppServerSlashCommandDescriptor)
    case mcp(AppServerMCPServerSummary)
    case skill(AppServerSkillSummary)

    var id: String {
        switch self {
        case .command(let command):
            return "command:\(command.id)"
        case .mcp(let server):
            return "mcp:\(server.id)"
        case .skill(let skill):
            return "skill:\(skill.id)"
        }
    }
}

func buildCommandPaletteRows(
    commands: [AppServerSlashCommandDescriptor],
    mcpServers: [AppServerMCPServerSummary],
    skills: [AppServerSkillSummary]
) -> [CommandPaletteRow] {
    var rows: [CommandPaletteRow] = []

    var seenCommandIDs: Set<String> = []
    for command in commands {
        guard seenCommandIDs.insert(command.id).inserted else { continue }
        rows.append(.command(command))
    }

    var seenMCPNames: Set<String> = []
    for server in mcpServers {
        guard seenMCPNames.insert(server.name).inserted else { continue }
        rows.append(.mcp(server))
    }

    var seenSkillIDs: Set<String> = []
    for skill in skills {
        guard seenSkillIDs.insert(skill.id).inserted else { continue }
        rows.append(.skill(skill))
    }

    return rows
}
