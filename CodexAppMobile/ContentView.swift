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
            && !password.isEmpty
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

struct ContentView: View {
    @EnvironmentObject private var store: ConnectionStore

    @State private var isPresentingEditor = false
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
            .navigationTitle("Connections")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        self.editingProfile = nil
                        self.editingPassword = ""
                        self.isPresentingEditor = true
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
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
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)

                    TextField("Host", text: self.$host)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)

                    TextField("Port", text: self.$portText)
                        .keyboardType(.numberPad)

                    TextField("Username", text: self.$username)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }

                Section("Authentication") {
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
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        self.saveTapped()
                    }
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
            self.validationMessage = "Fill all fields and set a password."
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
    @State private var password = ""
    @State private var commandInput = ""
    @State private var didLoadPassword = false

    var body: some View {
        VStack(spacing: 12) {
            connectionHeader

            outputPane

            commandBar
        }
        .padding()
        .navigationTitle(self.profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !self.didLoadPassword else { return }
            self.didLoadPassword = true
            self.password = self.store.password(for: self.profile.id)
        }
        .onDisappear {
            self.viewModel.disconnect()
        }
        .alert("Connection Error", isPresented: self.$viewModel.isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(self.viewModel.errorMessage)
        }
    }

    private var connectionHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(self.profile.username)@\(self.profile.host):\(self.profile.port)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack(spacing: 8) {
                if self.viewModel.state == .connected {
                    Button("Disconnect", role: .destructive) {
                        self.viewModel.disconnect()
                    }
                } else {
                    SecureField("Password", text: self.$password)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .disabled(self.viewModel.state == .connecting)

                    Button(self.viewModel.state == .connecting ? "Connecting..." : "Connect") {
                        self.store.updatePassword(self.password, for: self.profile.id)
                        self.viewModel.connect(profile: self.profile, password: self.password)
                    }
                    .disabled(self.password.isEmpty || self.viewModel.state == .connecting)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var outputPane: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(self.viewModel.output.isEmpty ? "No terminal output yet." : self.viewModel.output)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .textSelection(.enabled)
                    .id("terminal-end")
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .onChange(of: self.viewModel.output) { _, _ in
                withAnimation(.linear(duration: 0.1)) {
                    proxy.scrollTo("terminal-end", anchor: .bottom)
                }
            }
        }
    }

    private var commandBar: some View {
        HStack(spacing: 8) {
            TextField("Command", text: self.$commandInput)
                .font(.system(.body, design: .monospaced))
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .disabled(self.viewModel.state != .connected)
                .onSubmit {
                    self.sendCommand()
                }

            Button("Send") {
                self.sendCommand()
            }
            .disabled(self.viewModel.state != .connected || self.commandInput.isEmpty)
        }
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

final class TerminalSessionViewModel: ObservableObject {
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

    init() {
        self.engine.onOutput = { [weak self] text in
            self?.dispatchMain {
                self?.output += text
            }
        }

        self.engine.onConnected = { [weak self] in
            self?.dispatchMain {
                self?.state = .connected
                self?.output += "\n[connected]\n"
            }
        }

        self.engine.onDisconnected = { [weak self] in
            self?.dispatchMain {
                self?.state = .disconnected
                self?.output += "\n[disconnected]\n"
            }
        }

        self.engine.onError = { [weak self] message in
            self?.dispatchMain {
                self?.errorMessage = message
                self?.isShowingError = true
            }
        }
    }

    deinit {
        self.engine.disconnect()
    }

    func connect(profile: SSHConnectionProfile, password: String) {
        guard self.state != .connecting else {
            return
        }

        self.state = .connecting

        self.workerQueue.async { [weak self] in
            guard let self else { return }

            do {
                try self.engine.connect(
                    host: profile.host,
                    port: profile.port,
                    username: profile.username,
                    password: password
                )
            } catch {
                self.dispatchMain {
                    self.state = .disconnected
                    self.errorMessage = "Failed to connect: \(error.localizedDescription)"
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

    private func dispatchMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }
}

final class SSHClientEngine {
    enum EngineError: Error {
        case missingSSHHandler
        case missingSessionChannel
        case invalidChannelType
        case notConnected
    }

    var onOutput: ((String) -> Void)?
    var onConnected: (() -> Void)?
    var onDisconnected: (() -> Void)?
    var onError: ((String) -> Void)?

    private var eventLoopGroup: NIOTSEventLoopGroup?
    private var rootChannel: Channel?
    private var sessionChannel: Channel?

    func connect(host: String, port: Int, username: String, password: String) throws {
        self.disconnect()

        let group = NIOTSEventLoopGroup()
        self.eventLoopGroup = group

        let bootstrap = NIOTSConnectionBootstrap(group: group)
            .channelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    let sync = channel.pipeline.syncOperations
                    let sshHandler = NIOSSHHandler(
                        role: .client(
                            .init(
                                userAuthDelegate: SimplePasswordDelegate(username: username, password: password),
                                serverAuthDelegate: AcceptAllHostKeysDelegate()
                            )
                        ),
                        allocator: channel.allocator,
                        inboundChildChannelInitializer: nil
                    )

                    try sync.addHandler(sshHandler)
                    try sync.addHandler(RootErrorHandler { [weak self] message in
                        self?.onError?(message)
                    })
                }
            }

        do {
            let root = try bootstrap.connect(host: host, port: port).wait()
            self.rootChannel = root

            let sshHandler = try root.pipeline.handler(type: NIOSSHHandler.self).wait()

            let childChannelPromise = root.eventLoop.makePromise(of: Channel.self)

            sshHandler.createChannel(childChannelPromise, channelType: .session) { [weak self] childChannel, channelType in
                guard channelType == .session else {
                    return childChannel.eventLoop.makeFailedFuture(EngineError.invalidChannelType)
                }

                return childChannel.eventLoop.makeCompletedFuture {
                    try childChannel.pipeline.syncOperations.addHandler(
                        SessionOutputHandler(
                            onOutput: { [weak self] text in
                                self?.onOutput?(text)
                            },
                            onClosed: { [weak self] in
                                self?.onDisconnected?()
                            },
                            onError: { [weak self] message in
                                self?.onError?(message)
                            }
                        )
                    )
                }
            }

            self.sessionChannel = try childChannelPromise.futureResult.wait()
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
    private let onError: (String) -> Void

    init(
        onOutput: @escaping (String) -> Void,
        onClosed: @escaping () -> Void,
        onError: @escaping (String) -> Void
    ) {
        self.onOutput = onOutput
        self.onClosed = onClosed
        self.onError = onError
    }

    func channelActive(context: ChannelHandlerContext) {
        let ptyRequest = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: false,
            term: "xterm-256color",
            terminalCharacterWidth: 120,
            terminalRowHeight: 40,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0,
            terminalModes: SSHTerminalModes([:])
        )

        context.triggerUserOutboundEvent(ptyRequest, promise: nil)
        context.triggerUserOutboundEvent(SSHChannelRequestEvent.ShellRequest(wantReply: false), promise: nil)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channelData = self.unwrapInboundIn(data)

        guard case .byteBuffer(var buffer) = channelData.data,
              let text = buffer.readString(length: buffer.readableBytes),
              !text.isEmpty
        else {
            return
        }

        self.onOutput(text)
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
        self.onClosed()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        self.onError(error.localizedDescription)
        context.close(promise: nil)
    }
}

final class RootErrorHandler: ChannelInboundHandler {
    typealias InboundIn = Any

    private let onError: (String) -> Void

    init(onError: @escaping (String) -> Void) {
        self.onError = onError
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        self.onError(error.localizedDescription)
        context.close(promise: nil)
    }
}

final class AcceptAllHostKeysDelegate: NIOSSHClientServerAuthenticationDelegate {
    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        validationCompletePromise.succeed(())
    }
}

#Preview {
    ContentView()
        .environmentObject(ConnectionStore())
}
