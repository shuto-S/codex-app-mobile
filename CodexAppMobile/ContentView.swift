import SwiftUI
import Security
@preconcurrency import NIOCore
@preconcurrency import NIOSSH
@preconcurrency import NIOTransportServices

struct SSHConnectionProfile: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var host: String
    var port: Int
    var username: String

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int,
        username: String
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
    }
}

struct SSHConnectionDraft {
    var name: String
    var host: String
    var port: Int
    var username: String
    var password: String

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (1...65535).contains(port)
    }
}

@MainActor
final class ConnectionStore: ObservableObject {
    @Published private(set) var profiles: [SSHConnectionProfile] = []

    private let profilesKey = "ssh.connection.profiles.v1"

    init() {
        self.loadProfiles()
    }

    func upsert(profileID: UUID?, draft: SSHConnectionDraft) {
        let normalizedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedHost = draft.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedUser = draft.username.trimmingCharacters(in: .whitespacesAndNewlines)

        if let profileID,
           let index = self.profiles.firstIndex(where: { $0.id == profileID }) {
            self.profiles[index].name = normalizedName
            self.profiles[index].host = normalizedHost
            self.profiles[index].port = draft.port
            self.profiles[index].username = normalizedUser
            PasswordVault.save(password: draft.password, for: profileID)
        } else {
            let profile = SSHConnectionProfile(
                name: normalizedName,
                host: normalizedHost,
                port: draft.port,
                username: normalizedUser
            )
            self.profiles.append(profile)
            PasswordVault.save(password: draft.password, for: profile.id)
        }

        self.sortAndPersist()
    }

    func delete(profileID: UUID) {
        self.profiles.removeAll(where: { $0.id == profileID })
        PasswordVault.deletePassword(for: profileID)
        self.persistProfiles()
    }

    func password(for profileID: UUID) -> String {
        PasswordVault.readPassword(for: profileID) ?? ""
    }

    func updatePassword(_ password: String, for profileID: UUID) {
        PasswordVault.save(password: password, for: profileID)
    }

    private func loadProfiles() {
        guard let data = UserDefaults.standard.data(forKey: self.profilesKey) else {
            self.profiles = []
            return
        }

        do {
            self.profiles = try JSONDecoder().decode([SSHConnectionProfile].self, from: data)
            self.profiles.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            self.profiles = []
        }
    }

    private func sortAndPersist() {
        self.profiles.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        self.persistProfiles()
    }

    private func persistProfiles() {
        do {
            let data = try JSONEncoder().encode(self.profiles)
            UserDefaults.standard.set(data, forKey: self.profilesKey)
        } catch {
            UserDefaults.standard.removeObject(forKey: self.profilesKey)
        }
    }
}

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

        let attributes: [String: Any] = [
            kSecValueData as String: data,
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess {
            return
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
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
        self.hostKey.split(separator: " ").first.map(String.init) ?? "unknown"
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

struct ContentView: View {
    @EnvironmentObject private var store: ConnectionStore

    @State private var isPresentingEditor = false
    @State private var isPresentingKnownHosts = false
    @State private var editingProfile: SSHConnectionProfile?
    @State private var editingPassword = ""

    var body: some View {
        NavigationStack {
            Group {
                if self.store.profiles.isEmpty {
                    ContentUnavailableView(
                        "No Connections",
                        systemImage: "terminal",
                        description: Text("Tap + to add your first SSH endpoint.")
                    )
                } else {
                    List {
                        ForEach(self.store.profiles) { profile in
                            NavigationLink {
                                TerminalSessionView(profile: profile)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(profile.name)
                                        .font(.headline)
                                    Text("\(profile.username)@\(profile.host):\(profile.port)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Delete", role: .destructive) {
                                    self.store.delete(profileID: profile.id)
                                }

                                Button("Edit") {
                                    self.editingProfile = profile
                                    self.editingPassword = self.store.password(for: profile.id)
                                    self.isPresentingEditor = true
                                }
                                .tint(.orange)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(.systemBackground))
            .navigationTitle("Connections")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Known Hosts") {
                        self.isPresentingKnownHosts = true
                    }
                    .codexActionButtonStyle()
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        self.editingProfile = nil
                        self.editingPassword = ""
                        self.isPresentingEditor = true
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .codexActionButtonStyle()
                }
            }
        }
        .sheet(isPresented: self.$isPresentingEditor) {
            ConnectionEditorView(
                profile: self.editingProfile,
                initialPassword: self.editingPassword
            ) { draft in
                self.store.upsert(profileID: self.editingProfile?.id, draft: draft)
            }
        }
        .sheet(isPresented: self.$isPresentingKnownHosts) {
            KnownHostsView()
        }
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
                        "No Known Hosts",
                        systemImage: "lock.shield",
                        description: Text("Host keys are saved after the first successful connection.")
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
                                Button("Delete", role: .destructive) {
                                    HostKeyStore.remove(for: record.endpoint)
                                    self.reload()
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Known Hosts")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        self.dismiss()
                    }
                    .codexActionButtonStyle()
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Delete All", role: .destructive) {
                        self.isShowingDeleteAllConfirmation = true
                    }
                    .disabled(self.knownHosts.isEmpty)
                    .codexActionButtonStyle()
                }
            }
            .confirmationDialog(
                "Delete all stored host keys?",
                isPresented: self.$isShowingDeleteAllConfirmation
            ) {
                Button("Delete All", role: .destructive) {
                    self.knownHosts.forEach { HostKeyStore.remove(for: $0.endpoint) }
                    self.reload()
                    self.statusMessage = "All known hosts were removed."
                }
                Button("Cancel", role: .cancel) {}
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

struct ConnectionEditorView: View {
    let profile: SSHConnectionProfile?
    let onSave: (SSHConnectionDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var host: String
    @State private var portText: String
    @State private var username: String
    @State private var password: String

    @State private var validationMessage: String?

    init(
        profile: SSHConnectionProfile?,
        initialPassword: String,
        onSave: @escaping (SSHConnectionDraft) -> Void
    ) {
        self.profile = profile
        self.onSave = onSave

        _name = State(initialValue: profile?.name ?? "")
        _host = State(initialValue: profile?.host ?? "")
        _portText = State(initialValue: String(profile?.port ?? 22))
        _username = State(initialValue: profile?.username ?? "")
        _password = State(initialValue: initialPassword)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic") {
                    TextField("Name", text: self.$name)

                    TextField("Host", text: self.$host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)

                    TextField("Port", text: self.$portText)
                        .keyboardType(.numberPad)

                    TextField("Username", text: self.$username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                }

                Section("Authentication (Optional)") {
                    SecureField("Password", text: self.$password)
                }

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(self.profile == nil ? "New Connection" : "Edit Connection")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        self.dismiss()
                    }
                    .codexActionButtonStyle()
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        self.saveTapped()
                    }
                    .codexActionButtonStyle()
                }
            }
        }
    }

    private func saveTapped() {
        guard let port = Int(self.portText), (1...65535).contains(port) else {
            self.validationMessage = "Port must be between 1 and 65535."
            return
        }

        let draft = SSHConnectionDraft(
            name: self.name,
            host: self.host,
            port: port,
            username: self.username,
            password: self.password
        )

        guard draft.isValid else {
            self.validationMessage = "Fill all required fields."
            return
        }

        self.onSave(draft)
        self.dismiss()
    }
}

struct TerminalSessionView: View {
    let profile: SSHConnectionProfile

    @EnvironmentObject private var store: ConnectionStore

    @StateObject private var viewModel = TerminalSessionViewModel()
    @State private var commandInput = ""
    @State private var didStartAutoConnect = false
    @FocusState private var isCommandFieldFocused: Bool

    private var terminalText: String {
        self.viewModel.output.isEmpty ? "No terminal output yet." : self.viewModel.output
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
        .navigationTitle(self.profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !self.didStartAutoConnect else { return }
            self.didStartAutoConnect = true
            self.viewModel.connect(profile: self.profile, password: self.store.password(for: self.profile.id))
        }
        .onDisappear {
            self.viewModel.disconnect()
        }
        .alert("Connection Error", isPresented: self.$viewModel.isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(self.viewModel.errorMessage)
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if self.viewModel.state == .connected {
                    Button("Disconnect", role: .destructive) {
                        self.viewModel.disconnect()
                    }
                    .codexActionButtonStyle()
                }
            }
        }
        .ignoresSafeArea(.container, edges: [.horizontal, .bottom])
    }

    private var terminalBackground: some View {
        Color.black
            .ignoresSafeArea()
    }

    private var outputPane: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                Text(verbatim: self.terminalText)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Color(red: 0.82, green: 0.95, blue: 0.88))
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(16)
                    .textSelection(.enabled)
                    .id("terminal-end")
            }
            .background(
                Rectangle()
                    .fill(Color(red: 0.06, green: 0.08, blue: 0.11))
            )
            .onChange(of: self.viewModel.output) { _, _ in
                withAnimation(.linear(duration: 0.1)) {
                    proxy.scrollTo("terminal-end")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                self.isCommandFieldFocused = false
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var commandBar: some View {
        HStack(spacing: 10) {
            Text("›")
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .foregroundStyle(Color(red: 0.37, green: 0.88, blue: 0.72))

            TextField("Command", text: self.$commandInput)
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

            if self.isCommandFieldFocused {
                Button {
                    self.isCommandFieldFocused = false
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                }
                .codexActionButtonStyle()
                .accessibilityLabel("Hide Keyboard")
            }
        }
        .codexCardSurface()
    }

    private func sendCommand() {
        let trimmed = self.commandInput.trimmingCharacters(in: .newlines)
        guard !trimmed.isEmpty else {
            self.commandInput = ""
            return
        }

        self.viewModel.send(command: trimmed + "\n")
        self.commandInput = ""
    }

}

private struct CodexCardSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .padding(12)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            content
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

private extension View {
    func codexCardSurface() -> some View {
        self.modifier(CodexCardSurfaceModifier())
    }

    @ViewBuilder
    func codexActionButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}

final class TerminalSessionViewModel: ObservableObject, @unchecked Sendable {
    enum State {
        case disconnected
        case connecting
        case connected
    }

    @Published var state: State = .disconnected
    @Published var output: String = ""
    @Published var isShowingError = false
    @Published var errorMessage = ""

    private let engine = SSHClientEngine()
    private let workerQueue = DispatchQueue(label: "com.example.CodexAppMobile.ssh-session")
    private var activeEndpoint = "unknown host"

    init() {
        self.engine.onOutput = { [weak self] text in
            guard let self else { return }
            self.dispatchMain { [self] in
                self.output += text
            }
        }

        self.engine.onConnected = { [weak self] in
            guard let self else { return }
            self.dispatchMain { [self] in
                self.state = .connected
                self.output += "\n[connected]\n"
            }
        }

        self.engine.onDisconnected = { [weak self] in
            guard let self else { return }
            self.dispatchMain { [self] in
                self.state = .disconnected
                self.output += "\n[disconnected]\n"
            }
        }

        self.engine.onError = { [weak self] error in
            guard let self else { return }
            self.dispatchMain { [self] in
                self.state = .disconnected
                self.errorMessage = SSHConnectionErrorFormatter.message(for: error, endpoint: self.activeEndpoint)
                self.isShowingError = true
            }
        }
    }

    deinit {
        self.engine.disconnect()
    }

    func configureEndpoint(host: String, port: Int) {
        self.activeEndpoint = HostKeyStore.endpointKey(host: host, port: port)
    }

    func connect(profile: SSHConnectionProfile, password: String) {
        guard self.state == .disconnected else {
            return
        }

        self.configureEndpoint(host: profile.host, port: profile.port)
        self.state = .connecting

        self.workerQueue.async { [weak self] in
            guard let self else { return }

            do {
                try self.engine.connect(
                    host: profile.host,
                    port: profile.port,
                    username: profile.username,
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
                    self.errorMessage = "Failed to send command: \(error.localizedDescription)"
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
}

final class SSHClientEngine: @unchecked Sendable {
    enum EngineError: Error {
        case missingSSHHandler
        case missingSessionChannel
        case invalidChannelType
        case notConnected
    }

    var onOutput: (@Sendable (String) -> Void)?
    var onConnected: (@Sendable () -> Void)?
    var onDisconnected: (@Sendable () -> Void)?
    var onError: (@Sendable (Error) -> Void)?

    private var eventLoopGroup: NIOTSEventLoopGroup?
    private var rootChannel: Channel?
    private var sessionChannel: Channel?

    func connect(host: String, port: Int, username: String, password: String?) throws {
        self.disconnect()

        let group = NIOTSEventLoopGroup()
        self.eventLoopGroup = group
        let endpoint = HostKeyStore.endpointKey(host: host, port: port)
        let onOutput = self.onOutput
        let onDisconnected = self.onDisconnected
        let onError = self.onError

        let bootstrap = NIOTSConnectionBootstrap(group: group)
            .channelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    let sync = channel.pipeline.syncOperations
                    let userAuthDelegate = OptionalPasswordAuthenticationDelegate(username: username, password: password)
                    let hostKeyDelegate = TrustOnFirstUseHostKeysDelegate(endpoint: endpoint)
                    let sshHandler = NIOSSHHandler(
                        role: .client(
                            .init(
                                userAuthDelegate: userAuthDelegate,
                                serverAuthDelegate: hostKeyDelegate
                            )
                        ),
                        allocator: channel.allocator,
                        inboundChildChannelInitializer: nil
                    )

                    try sync.addHandler(sshHandler)
                    try sync.addHandler(RootErrorHandler { error in
                        onError?(error)
                    })
                }
            }

        do {
            let root = try bootstrap.connect(host: host, port: port).wait()
            self.rootChannel = root

            let sessionChannelFuture = root.pipeline.handler(type: NIOSSHHandler.self).flatMap { sshHandler in
                let childChannelPromise = root.eventLoop.makePromise(of: Channel.self)

                sshHandler.createChannel(childChannelPromise, channelType: .session) { childChannel, channelType in
                    guard channelType == .session else {
                        return childChannel.eventLoop.makeFailedFuture(EngineError.invalidChannelType)
                    }

                    let handler = SessionOutputHandler(
                        onOutput: { text in
                            onOutput?(text)
                        },
                        onClosed: {
                            onDisconnected?()
                        },
                        onError: { error in
                            onError?(error)
                        }
                    )
                    return childChannel.pipeline.addHandler(handler)
                }

                return childChannelPromise.futureResult
            }

            self.sessionChannel = try sessionChannelFuture.wait()
            self.onConnected?()
        } catch {
            self.disconnect()
            throw error
        }
    }

    func send(command: String) throws {
        guard let sessionChannel = self.sessionChannel else {
            throw EngineError.notConnected
        }

        var buffer = sessionChannel.allocator.buffer(capacity: command.utf8.count)
        buffer.writeString(command)

        let data = SSHChannelData(type: .channel, data: .byteBuffer(buffer))
        sessionChannel.writeAndFlush(data, promise: nil)
    }

    func disconnect() {
        self.sessionChannel?.close(promise: nil)
        self.sessionChannel = nil

        self.rootChannel?.close(promise: nil)
        self.rootChannel = nil

        if let eventLoopGroup = self.eventLoopGroup {
            self.eventLoopGroup = nil
            try? eventLoopGroup.syncShutdownGracefully()
        }

        self.onDisconnected?()
    }
}

final class SessionOutputHandler: ChannelInboundHandler {
    typealias InboundIn = SSHChannelData

    private let onOutput: (String) -> Void
    private let onClosed: () -> Void
    private let onError: (Error) -> Void
    private var pendingUTF8Data = Data()
    private var terminalEscapeFilter = TerminalEscapeFilter()

    init(
        onOutput: @escaping (String) -> Void,
        onClosed: @escaping () -> Void,
        onError: @escaping (Error) -> Void
    ) {
        self.onOutput = onOutput
        self.onClosed = onClosed
        self.onError = onError
    }

    func channelActive(context: ChannelHandlerContext) {
        let langRequest = SSHChannelRequestEvent.EnvironmentRequest(
            wantReply: false,
            name: "LANG",
            value: "en_US.UTF-8"
        )
        let lcCTypeRequest = SSHChannelRequestEvent.EnvironmentRequest(
            wantReply: false,
            name: "LC_CTYPE",
            value: "en_US.UTF-8"
        )
        let ptyRequest = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: false,
            term: "xterm-256color",
            terminalCharacterWidth: 120,
            terminalRowHeight: 40,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0,
            terminalModes: SSHTerminalModes([:])
        )

        context.triggerUserOutboundEvent(langRequest, promise: nil)
        context.triggerUserOutboundEvent(lcCTypeRequest, promise: nil)
        context.triggerUserOutboundEvent(ptyRequest, promise: nil)
        context.triggerUserOutboundEvent(SSHChannelRequestEvent.ShellRequest(wantReply: false), promise: nil)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channelData = self.unwrapInboundIn(data)

        guard case .byteBuffer(var buffer) = channelData.data else {
            return
        }

        let readableBytes = buffer.readableBytes
        guard readableBytes > 0,
              let chunk = buffer.readBytes(length: readableBytes)
        else {
            return
        }

        self.pendingUTF8Data.append(contentsOf: chunk)
        self.flushUTF8Buffer()
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let exitStatus = event as? SSHChannelRequestEvent.ExitStatus {
            self.onOutput("\n[remote exit status: \(exitStatus.exitStatus)]\n")
            context.close(promise: nil)
        } else {
            context.fireUserInboundEventTriggered(event)
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        self.flushRemainingUTF8BufferLossy()
        self.onClosed()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        self.onError(error)
        context.close(promise: nil)
    }

    private func flushUTF8Buffer() {
        while !self.pendingUTF8Data.isEmpty {
            if let text = String(data: self.pendingUTF8Data, encoding: .utf8) {
                self.emitSanitized(text)
                self.pendingUTF8Data.removeAll(keepingCapacity: true)
                return
            }

            let prefixLength = self.longestValidUTF8PrefixLength(in: self.pendingUTF8Data)
            if prefixLength > 0,
               let text = String(data: self.pendingUTF8Data.prefix(prefixLength), encoding: .utf8) {
                self.emitSanitized(text)
                self.pendingUTF8Data.removeFirst(prefixLength)
                continue
            }

            // UTF-8 は最大 4 バイトのため、4 バイト以下は次チャンクを待つ。
            if self.pendingUTF8Data.count <= 4 {
                return
            }

            let fallback = String(decoding: self.pendingUTF8Data.prefix(1), as: UTF8.self)
            self.emitSanitized(fallback)
            self.pendingUTF8Data.removeFirst()
        }
    }

    private func flushRemainingUTF8BufferLossy() {
        guard !self.pendingUTF8Data.isEmpty else { return }
        let remaining = String(decoding: self.pendingUTF8Data, as: UTF8.self)
        self.emitSanitized(remaining)
        self.pendingUTF8Data.removeAll(keepingCapacity: true)
    }

    private func longestValidUTF8PrefixLength(in data: Data) -> Int {
        var low = 1
        var high = data.count
        var best = 0

        while low <= high {
            let mid = (low + high) / 2
            if String(data: data.prefix(mid), encoding: .utf8) != nil {
                best = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        return best
    }

    private func emitSanitized(_ text: String) {
        guard !text.isEmpty else { return }
        let sanitized = self.terminalEscapeFilter.process(text)
        guard !sanitized.isEmpty else { return }
        self.onOutput(sanitized)
    }
}

private struct TerminalEscapeFilter {
    private enum State {
        case plain
        case esc
        case csi
        case osc
        case oscEsc
        case stString
        case stStringEsc
    }

    private var state: State = .plain

    mutating func process(_ input: String) -> String {
        var output = String.UnicodeScalarView()

        for scalar in input.unicodeScalars {
            let value = scalar.value

            switch self.state {
            case .plain:
                if value == 0x1B {
                    self.state = .esc
                    continue
                }
                if value == 0x9B {
                    self.state = .csi
                    continue
                }
                if value == 0x9D {
                    self.state = .osc
                    continue
                }
                if value == 0x90 {
                    self.state = .stString
                    continue
                }
                if value < 0x20, value != 0x09, value != 0x0A, value != 0x0D {
                    continue
                }
                if (0x80...0x9F).contains(value) {
                    continue
                }
                output.append(scalar)

            case .esc:
                switch scalar {
                case "[":
                    self.state = .csi
                case "]":
                    self.state = .osc
                case "P", "_", "^", "X":
                    self.state = .stString
                default:
                    self.state = .plain
                }

            case .csi:
                if (0x40...0x7E).contains(value) {
                    self.state = .plain
                } else if value == 0x1B {
                    self.state = .esc
                }

            case .osc:
                if value == 0x07 {
                    self.state = .plain
                } else if value == 0x1B {
                    self.state = .oscEsc
                }

            case .oscEsc:
                if scalar == "\\" {
                    self.state = .plain
                } else {
                    self.state = .osc
                }

            case .stString:
                if value == 0x1B {
                    self.state = .stStringEsc
                }

            case .stStringEsc:
                if scalar == "\\" {
                    self.state = .plain
                } else {
                    self.state = .stString
                }
            }
        }

        return String(output)
    }
}

final class RootErrorHandler: ChannelInboundHandler {
    typealias InboundIn = Any

    private let onError: (Error) -> Void

    init(onError: @escaping (Error) -> Void) {
        self.onError = onError
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        self.onError(error)
        context.close(promise: nil)
    }
}

enum SSHConnectionErrorFormatter {
    static func message(for error: Error, endpoint: String) -> String {
        if let validationError = error as? HostKeyValidationError {
            return validationError.localizedDescription
        }

        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain,
           let posixCode = POSIXErrorCode(rawValue: Int32(nsError.code)) {
            switch posixCode {
            case .ECONNREFUSED:
                return "Connection refused by \(endpoint). Ensure SSH server is running on the target host."
            case .ETIMEDOUT:
                return "Connection timed out for \(endpoint). Check VPN/Tailscale or network reachability."
            case .EHOSTUNREACH, .ENETUNREACH:
                return "Network is unreachable for \(endpoint)."
            default:
                break
            }
        }

        let description = nsError.localizedDescription
        let lowercased = description.lowercased()
        if lowercased.contains("permission denied")
            || lowercased.contains("authentication failed")
            || lowercased.contains("unable to authenticate") {
            return "Authentication failed for \(endpoint). Check username/password or server auth settings."
        }
        if lowercased.contains("host key") && lowercased.contains("mismatch") {
            return "Host key mismatch for \(endpoint). Re-register the host key only if rotation is intentional."
        }
        if lowercased.contains("timed out") {
            return "Connection timed out for \(endpoint)."
        }

        return "Connection failed for \(endpoint): \(description)"
    }
}

enum HostKeyValidationError: LocalizedError {
    case changedHostKey(endpoint: String)

    var errorDescription: String? {
        switch self {
        case .changedHostKey(let endpoint):
            return "Host key mismatch for \(endpoint). Remove the saved host key only if the server key rotation is intentional."
        }
    }
}

final class TrustOnFirstUseHostKeysDelegate: NIOSSHClientServerAuthenticationDelegate {
    private let endpoint: String

    init(endpoint: String) {
        self.endpoint = endpoint
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let presentedHostKey = String(openSSHPublicKey: hostKey)

        if let trustedHostKey = HostKeyStore.read(for: self.endpoint) {
            if trustedHostKey == presentedHostKey {
                validationCompletePromise.succeed(())
            } else {
                validationCompletePromise.fail(HostKeyValidationError.changedHostKey(endpoint: self.endpoint))
            }
            return
        }

        HostKeyStore.save(presentedHostKey, for: self.endpoint)
        validationCompletePromise.succeed(())
    }
}

public final class OptionalPasswordAuthenticationDelegate {
    private enum State {
        case tryNone
        case tryPassword
        case done
    }

    private var state: State = .tryNone
    private let username: String
    private let password: String?

    init(username: String, password: String?) {
        self.username = username
        self.password = password
    }
}

@available(*, unavailable)
extension OptionalPasswordAuthenticationDelegate: Sendable {}

extension OptionalPasswordAuthenticationDelegate: NIOSSHClientUserAuthenticationDelegate {
    public func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        switch self.state {
        case .tryNone:
            self.state = .tryPassword
            nextChallengePromise.succeed(
                NIOSSHUserAuthenticationOffer(
                    username: self.username,
                    serviceName: "",
                    offer: .none
                )
            )
        case .tryPassword:
            self.state = .done
            guard let password = self.password, availableMethods.contains(.password) else {
                nextChallengePromise.succeed(nil)
                return
            }
            nextChallengePromise.succeed(
                NIOSSHUserAuthenticationOffer(
                    username: self.username,
                    serviceName: "",
                    offer: .password(.init(password: password))
                )
            )
        case .done:
            nextChallengePromise.succeed(nil)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ConnectionStore())
}
