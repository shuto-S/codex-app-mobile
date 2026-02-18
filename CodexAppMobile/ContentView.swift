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
                Text("No terminal output yet.")
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
            .accessibilityLabel(self.isCommandFieldFocused ? "Hide Keyboard" : "Show Keyboard")
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

private struct ANSIRenderer {
    private enum State {
        case plain
        case esc
        case csi
        case osc
        case oscEsc
        case stString
        case stStringEsc
    }

    private struct RGBColor: Equatable {
        var red: Double
        var green: Double
        var blue: Double
    }

    private struct TextStyle: Equatable {
        var isBold = false
        var foregroundColor: RGBColor?
    }

    private struct Cell {
        var scalar: UnicodeScalar
        var style: TextStyle
        var isWide = false
        var isContinuation = false
    }

    private var state: State = .plain
    private var csiParameters = ""
    private var csiIntermediates = ""
    private var style = TextStyle()
    private var lines: [[Cell]] = [[]]
    private var cursorRow = 0
    private var cursorColumn = 0
    private var savedCursorRow = 0
    private var savedCursorColumn = 0
    private let defaultForeground = RGBColor(red: 0.82, green: 0.95, blue: 0.88)

    mutating func process(_ input: String) -> AttributedString {
        for scalar in input.unicodeScalars {
            let value = scalar.value

            switch self.state {
            case .plain:
                if value == 0x1B {
                    self.state = .esc
                    continue
                }
                if value == 0x9B {
                    self.beginCSI()
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
                if value == 0x0A {
                    self.lineFeed()
                    continue
                }
                if value == 0x0D {
                    self.carriageReturn()
                    continue
                }
                if value == 0x08 {
                    self.backspace()
                    continue
                }
                if value == 0x09 {
                    self.horizontalTab()
                    continue
                }
                if scalar == "\u{21A9}" || scalar == "\u{23CE}" {
                    continue
                }
                if value < 0x20 {
                    continue
                }
                if (0x80...0x9F).contains(value) {
                    continue
                }
                self.writeScalar(scalar)

            case .esc:
                switch scalar {
                case "[":
                    self.beginCSI()
                case "]":
                    self.state = .osc
                case "P", "_", "^", "X":
                    self.state = .stString
                default:
                    self.state = .plain
                }

            case .csi:
                if (0x30...0x3F).contains(value) {
                    self.csiParameters.unicodeScalars.append(scalar)
                } else if (0x20...0x2F).contains(value) {
                    self.csiIntermediates.unicodeScalars.append(scalar)
                } else if (0x40...0x7E).contains(value) {
                    self.handleCSI(final: scalar)
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
                self.state = scalar == "\\" ? .plain : .osc

            case .stString:
                if value == 0x1B {
                    self.state = .stStringEsc
                }

            case .stStringEsc:
                self.state = scalar == "\\" ? .plain : .stString
            }
        }

        return self.renderSnapshot()
    }

    private mutating func beginCSI() {
        self.csiParameters = ""
        self.csiIntermediates = ""
        self.state = .csi
    }

    private mutating func handleCSI(final: UnicodeScalar) {
        let params = self.parseCSIParameters(self.csiParameters)
        switch final {
        case "m":
            self.applySGR(parameters: params)
        case "K":
            self.eraseInLine(mode: params.first ?? 0)
        case "J":
            self.eraseInDisplay(mode: params.first ?? 0)
        case "C":
            self.cursorColumn += self.countParameter(params)
        case "D":
            self.cursorColumn = max(0, self.cursorColumn - self.countParameter(params))
        case "G":
            self.cursorColumn = max(0, self.positionParameter(params, index: 0) - 1)
        case "A":
            self.cursorRow = max(0, self.cursorRow - self.countParameter(params))
        case "B":
            self.cursorRow += self.countParameter(params)
            self.ensureCursorRowExists()
        case "E":
            self.cursorRow += self.countParameter(params)
            self.ensureCursorRowExists()
            self.cursorColumn = 0
        case "F":
            self.cursorRow = max(0, self.cursorRow - self.countParameter(params))
            self.cursorColumn = 0
        case "H", "f":
            let row = self.positionParameter(params, index: 0) - 1
            let column = self.positionParameter(params, index: 1) - 1
            self.cursorRow = max(0, row)
            self.ensureCursorRowExists()
            self.cursorColumn = max(0, column)
        case "s":
            self.savedCursorRow = self.cursorRow
            self.savedCursorColumn = self.cursorColumn
        case "u":
            self.cursorRow = max(0, self.savedCursorRow)
            self.ensureCursorRowExists()
            self.cursorColumn = max(0, self.savedCursorColumn)
        default:
            break
        }
    }

    private func parseCSIParameters(_ raw: String) -> [Int] {
        guard !raw.isEmpty else { return [] }
        let params = raw.split(separator: ";", omittingEmptySubsequences: false).map { part -> Int in
            Int(part) ?? 0
        }
        return params
    }

    private func countParameter(_ params: [Int], index: Int = 0) -> Int {
        guard index < params.count else { return 1 }
        let value = params[index]
        return value == 0 ? 1 : max(1, value)
    }

    private func positionParameter(_ params: [Int], index: Int) -> Int {
        guard index < params.count else { return 1 }
        let value = params[index]
        return value <= 0 ? 1 : value
    }

    private mutating func applySGR(parameters: [Int]) {
        let codes = parameters.isEmpty ? [0] : parameters
        var index = 0
        while index < codes.count {
            let code = codes[index]
            switch code {
            case 0:
                self.style = TextStyle()
            case 1:
                self.style.isBold = true
            case 22:
                self.style.isBold = false
            case 30...37:
                self.style.foregroundColor = self.baseColor(for: code - 30, bright: false)
            case 39:
                self.style.foregroundColor = nil
            case 90...97:
                self.style.foregroundColor = self.baseColor(for: code - 90, bright: true)
            case 38:
                if index + 2 < codes.count, codes[index + 1] == 5 {
                    self.style.foregroundColor = self.extended256Color(codes[index + 2])
                    index += 2
                } else if index + 4 < codes.count, codes[index + 1] == 2 {
                    let r = codes[index + 2]
                    let g = codes[index + 3]
                    let b = codes[index + 4]
                    self.style.foregroundColor = RGBColor(
                        red: Double(max(0, min(255, r))) / 255.0,
                        green: Double(max(0, min(255, g))) / 255.0,
                        blue: Double(max(0, min(255, b))) / 255.0
                    )
                    index += 4
                }
            default:
                break
            }
            index += 1
        }
    }

    private mutating func ensureCursorRowExists() {
        if self.lines.isEmpty {
            self.lines = [[]]
        }
        if self.cursorRow < 0 {
            self.cursorRow = 0
        }
        while self.cursorRow >= self.lines.count {
            self.lines.append([])
        }
        if self.cursorColumn < 0 {
            self.cursorColumn = 0
        }
    }

    private mutating func lineFeed() {
        self.cursorRow += 1
        if self.cursorRow >= self.lines.count {
            self.lines.append([])
        }
        self.cursorColumn = 0
    }

    private mutating func carriageReturn() {
        self.cursorColumn = 0
    }

    private mutating func backspace() {
        self.cursorColumn = max(0, self.cursorColumn - 1)
    }

    private mutating func horizontalTab() {
        let spaces = 8 - (self.cursorColumn % 8)
        for _ in 0..<spaces {
            self.writeScalar(" ")
        }
    }

    private mutating func writeScalar(_ scalar: UnicodeScalar) {
        self.ensureCursorRowExists()

        let width = self.displayWidth(of: scalar)
        guard width > 0 else { return }

        self.clearWideFragment(at: self.cursorColumn)
        if width == 2 {
            self.clearWideFragment(at: self.cursorColumn + 1)
        }

        self.ensureColumnExists(self.cursorColumn + width)
        self.lines[self.cursorRow][self.cursorColumn] = Cell(
            scalar: scalar,
            style: self.style,
            isWide: width == 2,
            isContinuation: false
        )

        if width == 2 {
            self.lines[self.cursorRow][self.cursorColumn + 1] = Cell(
                scalar: " ",
                style: self.style,
                isWide: false,
                isContinuation: true
            )
        }

        self.cursorColumn += width
    }

    private mutating func eraseInLine(mode: Int) {
        self.ensureCursorRowExists()

        switch mode {
        case 1:
            let upperBound = min(self.cursorColumn + 1, self.lines[self.cursorRow].count)
            guard upperBound > 0 else { return }
            let blank = self.blankCell()
            for index in 0..<upperBound {
                self.lines[self.cursorRow][index] = blank
            }
        case 2:
            self.lines[self.cursorRow].removeAll(keepingCapacity: true)
            self.cursorColumn = 0
        default:
            guard self.cursorColumn < self.lines[self.cursorRow].count else { return }
            self.lines[self.cursorRow].removeSubrange(self.cursorColumn..<self.lines[self.cursorRow].count)
        }
    }

    private mutating func eraseInDisplay(mode: Int) {
        switch mode {
        case 1:
            for row in 0..<min(self.cursorRow, self.lines.count) {
                self.lines[row].removeAll(keepingCapacity: true)
            }
            self.eraseInLine(mode: 1)
        case 2, 3:
            self.lines = [[]]
            self.cursorRow = 0
            self.cursorColumn = 0
            self.savedCursorRow = 0
            self.savedCursorColumn = 0
        default:
            self.eraseInLine(mode: 0)
            if self.cursorRow + 1 < self.lines.count {
                self.lines.removeSubrange((self.cursorRow + 1)..<self.lines.count)
            }
        }
    }

    private func renderSnapshot() -> AttributedString {
        guard !self.lines.isEmpty else { return AttributedString() }

        var result = AttributedString()
        for row in self.lines.indices {
            result += self.renderLine(self.lines[row])
            if row < self.lines.count - 1 {
                result += AttributedString("\n")
            }
        }
        return result
    }

    private func renderLine(_ line: [Cell]) -> AttributedString {
        guard !line.isEmpty else { return AttributedString() }

        var rendered = AttributedString()
        var runStyle = line[0].style
        var runText = ""

        func flushRun() {
            guard !runText.isEmpty else { return }
            var attributed = AttributedString(runText)
            attributed.font = runStyle.isBold
                ? .system(.body, design: .monospaced).weight(.semibold)
                : .system(.body, design: .monospaced)
            let color = runStyle.foregroundColor ?? self.defaultForeground
            attributed.foregroundColor = Color(red: color.red, green: color.green, blue: color.blue)
            rendered += attributed
            runText.removeAll(keepingCapacity: true)
        }

        for cell in line {
            if cell.isContinuation {
                continue
            }
            if cell.style != runStyle {
                flushRun()
                runStyle = cell.style
            }
            runText.unicodeScalars.append(cell.scalar)
        }

        flushRun()
        return rendered
    }

    private func baseColor(for index: Int, bright: Bool) -> RGBColor {
        let palette: [(Double, Double, Double)] = bright
            ? [
                (0.50, 0.50, 0.50),
                (1.00, 0.35, 0.35),
                (0.45, 0.90, 0.45),
                (1.00, 0.95, 0.45),
                (0.50, 0.68, 1.00),
                (1.00, 0.55, 1.00),
                (0.55, 0.95, 0.95),
                (1.00, 1.00, 1.00),
            ]
            : [
                (0.00, 0.00, 0.00),
                (0.75, 0.20, 0.20),
                (0.20, 0.70, 0.20),
                (0.78, 0.65, 0.20),
                (0.25, 0.45, 0.78),
                (0.70, 0.30, 0.70),
                (0.25, 0.70, 0.70),
                (0.80, 0.80, 0.80),
            ]
        let safeIndex = max(0, min(7, index))
        let color = palette[safeIndex]
        return RGBColor(red: color.0, green: color.1, blue: color.2)
    }

    private func extended256Color(_ code: Int) -> RGBColor {
        let clamped = max(0, min(255, code))

        if clamped < 16 {
            if clamped < 8 {
                return self.baseColor(for: clamped, bright: false)
            }
            return self.baseColor(for: clamped - 8, bright: true)
        }

        if clamped < 232 {
            let offset = clamped - 16
            let r = offset / 36
            let g = (offset % 36) / 6
            let b = offset % 6
            let component: (Int) -> Double = { value in
                value == 0 ? 0.0 : (Double(value) * 40.0 + 55.0) / 255.0
            }
            return RGBColor(red: component(r), green: component(g), blue: component(b))
        }

        let gray = Double((clamped - 232) * 10 + 8) / 255.0
        return RGBColor(red: gray, green: gray, blue: gray)
    }

    private func blankCell() -> Cell {
        Cell(scalar: " ", style: self.style, isWide: false, isContinuation: false)
    }

    private mutating func ensureColumnExists(_ targetExclusive: Int) {
        guard targetExclusive > self.lines[self.cursorRow].count else { return }
        let padCount = targetExclusive - self.lines[self.cursorRow].count
        guard padCount > 0 else { return }
        self.lines[self.cursorRow].append(contentsOf: Array(repeating: self.blankCell(), count: padCount))
    }

    private mutating func clearWideFragment(at column: Int) {
        guard column >= 0, column < self.lines[self.cursorRow].count else { return }

        if self.lines[self.cursorRow][column].isContinuation {
            self.lines[self.cursorRow][column] = self.blankCell()
            if column > 0, self.lines[self.cursorRow][column - 1].isWide {
                self.lines[self.cursorRow][column - 1] = self.blankCell()
            }
            return
        }

        if self.lines[self.cursorRow][column].isWide {
            self.lines[self.cursorRow][column] = self.blankCell()
            if column + 1 < self.lines[self.cursorRow].count,
               self.lines[self.cursorRow][column + 1].isContinuation {
                self.lines[self.cursorRow][column + 1] = self.blankCell()
            }
        }
    }

    private func displayWidth(of scalar: UnicodeScalar) -> Int {
        if scalar.properties.generalCategory == .nonspacingMark
            || scalar.properties.generalCategory == .enclosingMark
            || scalar.properties.generalCategory == .format {
            return 0
        }

        let value = scalar.value
        if (0x1100...0x115F).contains(value)
            || (0x2329...0x232A).contains(value)
            || (0x2E80...0xA4CF).contains(value)
            || (0xAC00...0xD7A3).contains(value)
            || (0xF900...0xFAFF).contains(value)
            || (0xFE10...0xFE19).contains(value)
            || (0xFE30...0xFE6F).contains(value)
            || (0xFF01...0xFF60).contains(value)
            || (0xFFE0...0xFFE6).contains(value)
            || (0x1F300...0x1FAFF).contains(value)
            || (0x20000...0x3FFFD).contains(value) {
            return 2
        }

        return 1
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

    init() {
        self.engine.onOutput = { [weak self] text in
            guard let self else { return }
            self.dispatchMain { [self] in
                self.appendRenderedOutput(text)
            }
        }

        self.engine.onConnected = { [weak self] in
            guard let self else { return }
            self.dispatchMain { [self] in
                self.suppressErrorsUntilNextConnect = false
                self.state = .connected
                self.ansiRenderer = ANSIRenderer()
                self.output = AttributedString()
            }
        }

        self.engine.onDisconnected = { [weak self] in
            guard let self else { return }
            self.dispatchMain { [self] in
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
        self.suppressErrorsUntilNextConnect = false
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

    private func appendRenderedOutput(_ text: String) {
        let rendered = self.ansiRenderer.process(text)
        self.output = rendered
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
    private var terminalQueryResponder = TerminalQueryResponder()

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
        self.flushUTF8Buffer(context: context)
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
        self.flushRemainingUTF8BufferLossy(context: nil)
        self.onClosed()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        self.onError(error)
        context.close(promise: nil)
    }

    private func flushUTF8Buffer(context: ChannelHandlerContext?) {
        while !self.pendingUTF8Data.isEmpty {
            if let text = String(data: self.pendingUTF8Data, encoding: .utf8) {
                self.emitRaw(text, context: context)
                self.pendingUTF8Data.removeAll(keepingCapacity: true)
                return
            }

            let prefixLength = self.longestValidUTF8PrefixLength(in: self.pendingUTF8Data)
            if prefixLength > 0,
               let text = String(data: self.pendingUTF8Data.prefix(prefixLength), encoding: .utf8) {
                self.emitRaw(text, context: context)
                self.pendingUTF8Data.removeFirst(prefixLength)
                continue
            }

            // UTF-8 は最大 4 バイトのため、4 バイト以下は次チャンクを待つ。
            if self.pendingUTF8Data.count <= 4 {
                return
            }

            let fallback = String(decoding: self.pendingUTF8Data.prefix(1), as: UTF8.self)
            self.emitRaw(fallback, context: context)
            self.pendingUTF8Data.removeFirst()
        }
    }

    private func flushRemainingUTF8BufferLossy(context: ChannelHandlerContext?) {
        guard !self.pendingUTF8Data.isEmpty else { return }
        let remaining = String(decoding: self.pendingUTF8Data, as: UTF8.self)
        self.emitRaw(remaining, context: context)
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

    private func emitRaw(_ text: String, context: ChannelHandlerContext?) {
        guard !text.isEmpty else { return }
        if let context {
            let responses = self.terminalQueryResponder.process(text)
            for response in responses {
                self.sendTerminalResponse(response, context: context)
            }
        } else {
            _ = self.terminalQueryResponder.process(text)
        }
        self.onOutput(text)
    }

    private func sendTerminalResponse(_ response: String, context: ChannelHandlerContext) {
        var buffer = context.channel.allocator.buffer(capacity: response.utf8.count)
        buffer.writeString(response)
        let data = SSHChannelData(type: .channel, data: .byteBuffer(buffer))
        context.channel.writeAndFlush(data, promise: nil)
    }
}

private struct TerminalQueryResponder {
    private enum State {
        case plain
        case esc
        case csi
    }

    private var state: State = .plain
    private var parameters = ""
    private var intermediates = ""

    mutating func process(_ input: String) -> [String] {
        var responses: [String] = []

        for scalar in input.unicodeScalars {
            let value = scalar.value

            switch self.state {
            case .plain:
                if value == 0x1B {
                    self.state = .esc
                    continue
                }
                if value == 0x9B {
                    self.beginCSI()
                    continue
                }

            case .esc:
                if scalar == "[" {
                    self.beginCSI()
                } else {
                    self.state = .plain
                }

            case .csi:
                if (0x30...0x3F).contains(value) {
                    self.parameters.unicodeScalars.append(scalar)
                } else if (0x20...0x2F).contains(value) {
                    self.intermediates.unicodeScalars.append(scalar)
                } else if (0x40...0x7E).contains(value) {
                    if let response = self.response(final: scalar) {
                        responses.append(response)
                    }
                    self.state = .plain
                } else if value == 0x1B {
                    self.state = .esc
                }
            }
        }

        return responses
    }

    private mutating func beginCSI() {
        self.parameters = ""
        self.intermediates = ""
        self.state = .csi
    }

    private func response(final: UnicodeScalar) -> String? {
        switch final {
        case "c":
            if self.intermediates == ">" {
                // Secondary Device Attributes response (xterm compatible)
                return "\u{1B}[>0;10;1c"
            }
            // Primary Device Attributes response (VT100 with advanced video option)
            if self.parameters.isEmpty || self.parameters == "0" {
                return "\u{1B}[?1;2c"
            }
            return nil

        case "n":
            let normalized = self.parameters.replacingOccurrences(of: "?", with: "")
            if normalized == "5" {
                // Device Status Report: "OK"
                return "\u{1B}[0n"
            }
            if normalized == "6" {
                // Cursor position report (home position as minimal fallback)
                return "\u{1B}[1;1R"
            }
            return nil

        default:
            return nil
        }
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
