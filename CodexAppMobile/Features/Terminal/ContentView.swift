import SwiftUI
import Security

enum PasswordVault {
    private static let service = "com.example.CodexAppMobile.ssh"

    static func save(password: String, for profileID: UUID) {
        let account = self.account(for: profileID)
        let data = Data(password.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func readPassword(for profileID: UUID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: self.account(for: profileID),
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return password
    }

    static func deletePassword(for profileID: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: self.account(for: profileID),
        ]

        SecItemDelete(query as CFDictionary)
    }

    private static func account(for profileID: UUID) -> String {
        "profile.\(profileID.uuidString)"
    }
}

enum HostKeyStore {
    private static let knownHostsKey = "ssh.known-hosts.v1"

    static func endpointKey(host: String, port: Int) -> String {
        "\(host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()):\(port)"
    }

    static func read(for endpoint: String, defaults: UserDefaults = .standard) -> String? {
        let hosts = defaults.dictionary(forKey: self.knownHostsKey) as? [String: String]
        return hosts?[endpoint]
    }

    static func save(_ hostKey: String, for endpoint: String, defaults: UserDefaults = .standard) {
        var hosts = defaults.dictionary(forKey: self.knownHostsKey) as? [String: String] ?? [:]
        hosts[endpoint] = hostKey
        defaults.set(hosts, forKey: self.knownHostsKey)
    }

    static func remove(for endpoint: String, defaults: UserDefaults = .standard) {
        var hosts = defaults.dictionary(forKey: self.knownHostsKey) as? [String: String] ?? [:]
        hosts.removeValue(forKey: endpoint)
        defaults.set(hosts, forKey: self.knownHostsKey)
    }

    static func all(defaults: UserDefaults = .standard) -> [KnownHostRecord] {
        let hosts = defaults.dictionary(forKey: self.knownHostsKey) as? [String: String] ?? [:]
        return hosts
            .map { KnownHostRecord(endpoint: $0.key, hostKey: $0.value) }
            .sorted { $0.endpoint.localizedCaseInsensitiveCompare($1.endpoint) == .orderedAscending }
    }
}

struct KnownHostRecord: Identifiable, Equatable {
    let endpoint: String
    let hostKey: String

    var id: String { self.endpoint }

    var algorithm: String {
        self.hostKey.split(separator: " ").first.map(String.init) ?? L10n.text("unknown")
    }

    var keyPreview: String {
        let compact = self.hostKey.replacingOccurrences(of: " ", with: "")
        if compact.count <= 26 {
            return compact
        }
        let prefix = compact.prefix(10)
        let suffix = compact.suffix(10)
        return "\(prefix)...\(suffix)"
    }
}

struct TerminalView: View {
    @EnvironmentObject private var appState: AppState

    @State private var isPresentingKnownHosts = false
    @State private var navigationPath: [UUID] = []
    @State private var consumedLaunchRequestID: UUID?

    var body: some View {
        NavigationStack(path: self.$navigationPath) {
            Group {
                if self.appState.remoteHostStore.hosts.isEmpty {
                    ContentUnavailableView(
                        L10n.text("No Hosts"),
                        systemImage: "terminal",
                        description: Text(L10n.text("Add a host from Hosts first."))
                    )
                } else {
                    List {
                        ForEach(self.appState.remoteHostStore.hosts) { host in
                            NavigationLink(value: host.id) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(host.name)
                                        .font(.headline)
                                    Text("\(host.username)@\(host.host):\(host.sshPort)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                }
            }
            .navigationDestination(for: UUID.self) { hostID in
                if let host = self.appState.remoteHostStore.hosts.first(where: { $0.id == hostID }) {
                    TerminalSessionView(
                        host: host,
                        initialCommand: self.initialCommand(for: hostID)
                    )
                } else {
                    Text(L10n.text("Host not found."))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(.systemBackground))
            .navigationTitle(L10n.text("Terminal"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.text("Known Hosts")) {
                        self.isPresentingKnownHosts = true
                    }
                    .codexActionButtonStyle()
                }
            }
        }
        .sheet(isPresented: self.$isPresentingKnownHosts) {
            KnownHostsView()
        }
        .onAppear {
            self.consumeLaunchContextIfNeeded()
        }
        .onChange(of: self.appState.terminalLaunchContext) {
            self.consumeLaunchContextIfNeeded()
        }
    }

    private func initialCommand(for hostID: UUID) -> String? {
        guard let launchContext = self.appState.terminalLaunchContext,
              launchContext.hostID == hostID else {
            return nil
        }
        return launchContext.initialCommand
    }

    private func consumeLaunchContextIfNeeded() {
        guard let launchContext = self.appState.terminalLaunchContext else {
            return
        }
        guard self.consumedLaunchRequestID != launchContext.id else {
            return
        }

        self.navigationPath = [launchContext.hostID]
        self.consumedLaunchRequestID = launchContext.id
    }
}

struct KnownHostsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var knownHosts = HostKeyStore.all()
    @State private var isShowingDeleteAllConfirmation = false
    @State private var statusMessage = ""

    var body: some View {
        NavigationStack {
            Group {
                if self.knownHosts.isEmpty {
                    ContentUnavailableView(
                        L10n.text("No Known Hosts"),
                        systemImage: "lock.shield",
                        description: Text(L10n.text("Host keys are saved after the first successful connection."))
                    )
                } else {
                    List {
                        ForEach(self.knownHosts) { record in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(record.endpoint)
                                    .font(.headline)
                                    .textSelection(.enabled)
                                Text(record.algorithm)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(record.keyPreview)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(L10n.text("Delete"), role: .destructive) {
                                    HostKeyStore.remove(for: record.endpoint)
                                    self.reload()
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(L10n.text("Known Hosts"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        self.dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(L10n.text("Close"))
                    .codexActionButtonStyle()
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.text("Delete All"), role: .destructive) {
                        self.isShowingDeleteAllConfirmation = true
                    }
                    .disabled(self.knownHosts.isEmpty)
                    .codexActionButtonStyle()
                }
            }
            .confirmationDialog(
                L10n.text("Delete all stored host keys?"),
                isPresented: self.$isShowingDeleteAllConfirmation
            ) {
                Button(L10n.text("Delete All"), role: .destructive) {
                    self.knownHosts.forEach { HostKeyStore.remove(for: $0.endpoint) }
                    self.reload()
                    self.statusMessage = L10n.text("All known hosts were removed.")
                }
                Button(L10n.text("Cancel"), role: .cancel) {}
            }
            .safeAreaInset(edge: .bottom) {
                if !self.statusMessage.isEmpty {
                    Text(self.statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
            }
            .onAppear {
                self.reload()
            }
        }
    }

    private func reload() {
        self.knownHosts = HostKeyStore.all()
    }
}

struct TerminalSessionView: View {
    let host: RemoteHost
    let initialCommand: String?

    @EnvironmentObject private var appState: AppState

    @StateObject private var viewModel = TerminalSessionViewModel()
    @State private var commandInput = ""
    @State private var didStartAutoConnect = false
    @State private var pendingInitialCommand: String?
    @FocusState private var isCommandFieldFocused: Bool

    private var hasTerminalOutput: Bool {
        !self.viewModel.output.characters.isEmpty
    }

    var body: some View {
        ZStack {
            terminalBackground

            outputPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            commandBar
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
        }
        .navigationTitle(self.host.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !self.didStartAutoConnect else { return }
            self.didStartAutoConnect = true
            self.pendingInitialCommand = self.initialCommand
            self.viewModel.connect(host: self.host, password: self.appState.remoteHostStore.password(for: self.host.id))
        }
        .onChange(of: self.appState.terminalLaunchContext) {
            self.consumeLaunchContextIfNeeded()
        }
        .onChange(of: self.viewModel.state) {
            self.sendPendingInitialCommandIfNeeded()
        }
        .onDisappear {
            self.viewModel.disconnect()
        }
        .alert(L10n.text("Connection Error"), isPresented: self.$viewModel.isShowingError) {
            Button(L10n.text("OK"), role: .cancel) {}
        } message: {
            Text(self.viewModel.errorMessage)
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if self.viewModel.state == .connected {
                    Button(L10n.text("Disconnect"), role: .destructive) {
                        self.viewModel.disconnect()
                    }
                    .codexActionButtonStyle()
                }
            }
        }
        .ignoresSafeArea(.container, edges: .horizontal)
    }

    private var terminalBackground: some View {
        Color.black
            .ignoresSafeArea()
    }

    private var outputPane: some View {
        ScrollView(.vertical) {
            if self.hasTerminalOutput {
                Text(self.viewModel.output)
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(16)
                    .textSelection(.enabled)
            } else {
                Text(L10n.text("No terminal output yet."))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Color(red: 0.82, green: 0.95, blue: 0.88))
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(16)
            }
        }
        .background(
            Rectangle()
                .fill(Color(red: 0.06, green: 0.08, blue: 0.11))
        )
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture {
            self.isCommandFieldFocused = false
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var commandBar: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 10) {
                Text("›")
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Color(red: 0.37, green: 0.88, blue: 0.72))

                TextField(L10n.text("Command"), text: self.$commandInput)
                    .font(.system(.body, design: .monospaced))
                    .keyboardType(.default)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .submitLabel(.send)
                    .focused(self.$isCommandFieldFocused)
                    .disabled(self.viewModel.state != .connected)
                    .onSubmit {
                        self.sendCommand()
                    }
                    .padding(.vertical, 6)
                    .layoutPriority(1)
            }
            .padding(.trailing, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .codexCardSurface()
            .contentShape(Rectangle())
            .onTapGesture {
                guard self.viewModel.state == .connected else { return }
                self.isCommandFieldFocused = true
            }

            Button {
                guard self.viewModel.state == .connected else { return }
                self.isCommandFieldFocused.toggle()
            } label: {
                Image(
                    systemName: self.isCommandFieldFocused
                        ? "keyboard.chevron.compact.down"
                        : "keyboard"
                )
            }
            .codexActionButtonStyle()
            .accessibilityLabel(self.isCommandFieldFocused ? L10n.text("Hide Keyboard") : L10n.text("Show Keyboard"))
            .disabled(self.viewModel.state != .connected)
            .frame(width: 52, alignment: .trailing)
        }
    }

    private func sendCommand() {
        let normalized = self.commandInput
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            self.commandInput = ""
            return
        }

        self.viewModel.send(command: trimmed + "\n")
        self.commandInput = ""
    }

    private func consumeLaunchContextIfNeeded() {
        guard let launchContext = self.appState.terminalLaunchContext,
              launchContext.hostID == self.host.id else {
            return
        }
        self.pendingInitialCommand = launchContext.initialCommand
        self.sendPendingInitialCommandIfNeeded()
    }

    private func sendPendingInitialCommandIfNeeded() {
        guard self.viewModel.state == .connected,
              let pendingInitialCommand,
              !pendingInitialCommand.isEmpty else {
            return
        }

        self.viewModel.send(command: pendingInitialCommand + "\n")
        self.pendingInitialCommand = nil
    }

}



final class TerminalSessionViewModel: ObservableObject, @unchecked Sendable {
    enum State {
        case disconnected
        case connecting
        case connected
    }

    @Published var state: State = .disconnected
    @Published var output = AttributedString()
    @Published var isShowingError = false
    @Published var errorMessage = ""

    private let engine = SSHClientEngine()
    private let workerQueue = DispatchQueue(label: "com.example.CodexAppMobile.ssh-session")
    private var activeEndpoint = "unknown host"
    private var ansiRenderer = ANSIRenderer()
    private var suppressErrorsUntilNextConnect = false
    private var pendingOutputBuffer = ""
    private var scheduledFlushTask: Task<Void, Never>?
    private let outputLineLimit = 2_000
    private let outputFlushIntervalNanoseconds: UInt64 = 33_000_000

    init() {
        self.engine.onOutput = { [weak self] text in
            guard let self else { return }
            self.dispatchMain { [self] in
                self.enqueueOutputChunk(text)
            }
        }

        self.engine.onConnected = { [weak self] in
            guard let self else { return }
            self.dispatchMain { [self] in
                self.suppressErrorsUntilNextConnect = false
                self.state = .connected
            }
        }

        self.engine.onDisconnected = { [weak self] in
            guard let self else { return }
            self.dispatchMain { [self] in
                self.flushPendingOutput()
                self.state = .disconnected
            }
        }

        self.engine.onError = { [weak self] error in
            guard let self else { return }
            self.dispatchMain { [self] in
                self.state = .disconnected
                guard !self.suppressErrorsUntilNextConnect else {
                    return
                }
                self.errorMessage = SSHConnectionErrorFormatter.message(for: error, endpoint: self.activeEndpoint)
                self.isShowingError = true
            }
        }
    }

    deinit {
        self.scheduledFlushTask?.cancel()
        self.scheduledFlushTask = nil
        self.engine.disconnect()
    }

    func configureEndpoint(host: String, port: Int) {
        self.activeEndpoint = HostKeyStore.endpointKey(host: host, port: port)
    }

    func connect(host: RemoteHost, password: String) {
        guard self.state == .disconnected else {
            return
        }

        self.configureEndpoint(host: host.host, port: host.sshPort)
        self.suppressErrorsUntilNextConnect = false
        self.scheduledFlushTask?.cancel()
        self.scheduledFlushTask = nil
        self.pendingOutputBuffer = ""
        self.ansiRenderer = ANSIRenderer()
        self.output = AttributedString()
        self.state = .connecting

        self.workerQueue.async { [weak self] in
            guard let self else { return }

            do {
                try self.engine.connect(
                    host: host.host,
                    port: host.sshPort,
                    username: host.username,
                    password: password.isEmpty ? nil : password
                )
            } catch {
                self.dispatchMain {
                    self.state = .disconnected
                    self.errorMessage = SSHConnectionErrorFormatter.message(for: error, endpoint: self.activeEndpoint)
                    self.isShowingError = true
                }
            }
        }
    }

    func disconnect() {
        self.suppressErrorsUntilNextConnect = true
        self.workerQueue.async { [weak self] in
            self?.engine.disconnect()
        }
    }

    func send(command: String) {
        self.workerQueue.async { [weak self] in
            guard let self else { return }

            do {
                try self.engine.send(command: command)
            } catch {
                self.dispatchMain {
                    self.errorMessage = L10n.format("Failed to send command: %@", error.localizedDescription)
                    self.isShowingError = true
                }
            }
        }
    }

    private func dispatchMain(_ block: @escaping @Sendable () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }

    private func enqueueOutputChunk(_ text: String) {
        guard !text.isEmpty else { return }
        self.pendingOutputBuffer += text
        guard self.scheduledFlushTask == nil else { return }

        self.scheduledFlushTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.outputFlushIntervalNanoseconds)
            guard !Task.isCancelled else { return }
            self.flushPendingOutput()
        }
    }

    private func flushPendingOutput() {
        self.scheduledFlushTask?.cancel()
        self.scheduledFlushTask = nil
        let buffered = self.pendingOutputBuffer
        self.pendingOutputBuffer = ""
        guard !buffered.isEmpty else { return }

        let rendered = self.ansiRenderer.process(buffered, lineLimit: self.outputLineLimit)
        self.output = rendered
    }
}


#Preview {
    TerminalView()
        .environmentObject(AppState())
}
