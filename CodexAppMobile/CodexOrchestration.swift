import Foundation
import SwiftUI

enum TransportKind: String, Codable, CaseIterable, Identifiable {
    case appServerWS
    case ssh

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .appServerWS:
            return "App Server (WebSocket)"
        case .ssh:
            return "SSH"
        }
    }
}

enum ConnectionAuthMode: String, Codable, CaseIterable, Identifiable {
    case remotePCManaged

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .remotePCManaged:
            return "Remote PC Managed"
        }
    }
}

enum CodexApprovalPolicy: String, Codable, CaseIterable, Identifiable {
    case untrusted
    case onFailure = "on-failure"
    case onRequest = "on-request"
    case never

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .untrusted:
            return "untrusted"
        case .onFailure:
            return "on-failure"
        case .onRequest:
            return "on-request"
        case .never:
            return "never"
        }
    }
}

struct RemoteConnection: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var host: String
    var sshPort: Int
    var username: String
    var appServerURL: String
    var preferredTransport: TransportKind
    var authMode: ConnectionAuthMode
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        sshPort: Int,
        username: String,
        appServerURL: String,
        preferredTransport: TransportKind = .appServerWS,
        authMode: ConnectionAuthMode = .remotePCManaged,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.sshPort = sshPort
        self.username = username
        self.appServerURL = appServerURL
        self.preferredTransport = preferredTransport
        self.authMode = authMode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static func defaultAppServerURL(host: String, port: Int = 8080) -> String {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        return "ws://\(normalizedHost):\(port)"
    }
}

struct RemoteConnectionDraft {
    var name: String
    var host: String
    var sshPort: Int
    var username: String
    var appServerURL: String
    var preferredTransport: TransportKind
    var authMode: ConnectionAuthMode
    var password: String

    static let empty = RemoteConnectionDraft(
        name: "",
        host: "",
        sshPort: 22,
        username: "",
        appServerURL: "",
        preferredTransport: .appServerWS,
        authMode: .remotePCManaged,
        password: ""
    )

    var isValid: Bool {
        let trimmedName = self.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHost = self.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUser = self.username.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty,
              !trimmedHost.isEmpty,
              !trimmedUser.isEmpty,
              (1...65535).contains(self.sshPort),
              let url = URL(string: self.appServerURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "ws" || scheme == "wss"
        else {
            return false
        }

        return true
    }

    init(
        name: String,
        host: String,
        sshPort: Int,
        username: String,
        appServerURL: String,
        preferredTransport: TransportKind,
        authMode: ConnectionAuthMode,
        password: String
    ) {
        self.name = name
        self.host = host
        self.sshPort = sshPort
        self.username = username
        self.appServerURL = appServerURL
        self.preferredTransport = preferredTransport
        self.authMode = authMode
        self.password = password
    }

    init(connection: RemoteConnection, password: String) {
        self.name = connection.name
        self.host = connection.host
        self.sshPort = connection.sshPort
        self.username = connection.username
        self.appServerURL = connection.appServerURL
        self.preferredTransport = connection.preferredTransport
        self.authMode = connection.authMode
        self.password = password
    }
}

struct ProjectWorkspace: Identifiable, Codable, Equatable {
    let id: UUID
    var connectionID: UUID
    var name: String
    var remotePath: String
    var defaultModel: String
    var defaultApprovalPolicy: CodexApprovalPolicy
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        connectionID: UUID,
        name: String,
        remotePath: String,
        defaultModel: String = "",
        defaultApprovalPolicy: CodexApprovalPolicy = .onRequest,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.connectionID = connectionID
        self.name = name
        self.remotePath = remotePath
        self.defaultModel = defaultModel
        self.defaultApprovalPolicy = defaultApprovalPolicy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var displayName: String {
        let trimmed = self.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? self.remotePath : trimmed
    }
}

struct ProjectWorkspaceDraft {
    var name: String
    var remotePath: String
    var defaultModel: String
    var defaultApprovalPolicy: CodexApprovalPolicy

    static let empty = ProjectWorkspaceDraft(
        name: "",
        remotePath: "",
        defaultModel: "",
        defaultApprovalPolicy: .onRequest
    )

    var isValid: Bool {
        !self.remotePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(
        name: String,
        remotePath: String,
        defaultModel: String,
        defaultApprovalPolicy: CodexApprovalPolicy
    ) {
        self.name = name
        self.remotePath = remotePath
        self.defaultModel = defaultModel
        self.defaultApprovalPolicy = defaultApprovalPolicy
    }

    init(workspace: ProjectWorkspace) {
        self.name = workspace.name
        self.remotePath = workspace.remotePath
        self.defaultModel = workspace.defaultModel
        self.defaultApprovalPolicy = workspace.defaultApprovalPolicy
    }
}

struct CodexThreadSummary: Identifiable, Codable, Equatable {
    var id: String { "\(self.workspaceID.uuidString):\(self.threadID)" }

    var threadID: String
    var connectionID: UUID
    var workspaceID: UUID
    var preview: String
    var updatedAt: Date
    var archived: Bool
    var cwd: String
}

enum CodexTurnItem: Equatable, Identifiable {
    case userMessage(id: String, text: String)
    case agentMessage(id: String, text: String)
    case plan(id: String, text: String)
    case reasoning(id: String, text: String)
    case commandExecution(id: String, command: String, status: String, output: String?)
    case fileChange(id: String, status: String, changedFiles: Int)
    case other(id: String, type: String)

    var id: String {
        switch self {
        case .userMessage(let id, _),
                .agentMessage(let id, _),
                .plan(let id, _),
                .reasoning(let id, _),
                .commandExecution(let id, _, _, _),
                .fileChange(let id, _, _),
                .other(let id, _):
            return id
        }
    }
}

struct CodexTurn: Identifiable, Equatable {
    let id: String
    let status: String
    let items: [CodexTurnItem]
}

struct CodexThreadDetail: Equatable {
    let threadID: String
    let turns: [CodexTurn]
}

protocol ConnectionCredentialStore {
    func save(password: String, for connectionID: UUID)
    func readPassword(for connectionID: UUID) -> String?
    func deletePassword(for connectionID: UUID)
}

struct KeychainConnectionCredentialStore: ConnectionCredentialStore {
    func save(password: String, for connectionID: UUID) {
        PasswordVault.save(password: password, for: connectionID)
    }

    func readPassword(for connectionID: UUID) -> String? {
        PasswordVault.readPassword(for: connectionID)
    }

    func deletePassword(for connectionID: UUID) {
        PasswordVault.deletePassword(for: connectionID)
    }
}

final class InMemoryConnectionCredentialStore: ConnectionCredentialStore {
    private var values: [UUID: String] = [:]

    func save(password: String, for connectionID: UUID) {
        self.values[connectionID] = password
    }

    func readPassword(for connectionID: UUID) -> String? {
        self.values[connectionID]
    }

    func deletePassword(for connectionID: UUID) {
        self.values.removeValue(forKey: connectionID)
    }
}

@MainActor
final class RemoteConnectionStore: ObservableObject {
    @Published private(set) var connections: [RemoteConnection] = []

    private let defaults: UserDefaults
    private let credentialStore: ConnectionCredentialStore

    private let connectionsKey = "codex.remote.connections.v1"
    private let legacyProfilesKey = "ssh.connection.profiles.v1"

    init(
        defaults: UserDefaults = .standard,
        credentialStore: ConnectionCredentialStore = KeychainConnectionCredentialStore()
    ) {
        self.defaults = defaults
        self.credentialStore = credentialStore
        self.loadConnections()
    }

    func upsert(connectionID: UUID?, draft: RemoteConnectionDraft) {
        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHost = draft.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUser = draft.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = draft.appServerURL.trimmingCharacters(in: .whitespacesAndNewlines)

        if let connectionID,
           let index = self.connections.firstIndex(where: { $0.id == connectionID }) {
            self.connections[index].name = trimmedName
            self.connections[index].host = trimmedHost
            self.connections[index].sshPort = draft.sshPort
            self.connections[index].username = trimmedUser
            self.connections[index].appServerURL = trimmedURL
            self.connections[index].preferredTransport = draft.preferredTransport
            self.connections[index].authMode = draft.authMode
            self.connections[index].updatedAt = Date()
            self.credentialStore.save(password: draft.password, for: connectionID)
        } else {
            let connection = RemoteConnection(
                name: trimmedName,
                host: trimmedHost,
                sshPort: draft.sshPort,
                username: trimmedUser,
                appServerURL: trimmedURL,
                preferredTransport: draft.preferredTransport,
                authMode: draft.authMode
            )
            self.connections.append(connection)
            self.credentialStore.save(password: draft.password, for: connection.id)
        }

        self.sortAndPersist()
    }

    func delete(connectionID: UUID) {
        self.connections.removeAll(where: { $0.id == connectionID })
        self.credentialStore.deletePassword(for: connectionID)
        self.persistConnections()
    }

    func password(for connectionID: UUID) -> String {
        self.credentialStore.readPassword(for: connectionID) ?? ""
    }

    func updatePassword(_ password: String, for connectionID: UUID) {
        self.credentialStore.save(password: password, for: connectionID)
    }

    private func loadConnections() {
        if let data = self.defaults.data(forKey: self.connectionsKey),
           let decoded = try? JSONDecoder().decode([RemoteConnection].self, from: data) {
            self.connections = decoded
            self.connections.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            return
        }

        self.connections = self.migrateFromLegacyProfilesIfNeeded()
        self.sortAndPersist()
    }

    private func migrateFromLegacyProfilesIfNeeded() -> [RemoteConnection] {
        guard let data = self.defaults.data(forKey: self.legacyProfilesKey),
              let legacyProfiles = try? JSONDecoder().decode([SSHConnectionProfile].self, from: data)
        else {
            return []
        }

        return legacyProfiles.map { profile in
            RemoteConnection(
                id: profile.id,
                name: profile.name,
                host: profile.host,
                sshPort: profile.port,
                username: profile.username,
                appServerURL: RemoteConnection.defaultAppServerURL(host: profile.host)
            )
        }
    }

    private func sortAndPersist() {
        self.connections.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        self.persistConnections()
    }

    private func persistConnections() {
        guard let data = try? JSONEncoder().encode(self.connections) else {
            self.defaults.removeObject(forKey: self.connectionsKey)
            return
        }
        self.defaults.set(data, forKey: self.connectionsKey)
    }
}

@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var workspaces: [ProjectWorkspace] = []

    private let defaults: UserDefaults
    private let workspacesKey = "codex.project.workspaces.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.loadWorkspaces()
    }

    func workspaces(for connectionID: UUID?) -> [ProjectWorkspace] {
        guard let connectionID else { return [] }
        return self.workspaces.filter { $0.connectionID == connectionID }
    }

    func upsert(workspaceID: UUID?, connectionID: UUID, draft: ProjectWorkspaceDraft) {
        let trimmedPath = draft.remotePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = draft.defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)

        if let workspaceID,
           let index = self.workspaces.firstIndex(where: { $0.id == workspaceID }) {
            self.workspaces[index].connectionID = connectionID
            self.workspaces[index].name = trimmedName
            self.workspaces[index].remotePath = trimmedPath
            self.workspaces[index].defaultModel = trimmedModel
            self.workspaces[index].defaultApprovalPolicy = draft.defaultApprovalPolicy
            self.workspaces[index].updatedAt = Date()
        } else {
            self.workspaces.append(
                ProjectWorkspace(
                    connectionID: connectionID,
                    name: trimmedName,
                    remotePath: trimmedPath,
                    defaultModel: trimmedModel,
                    defaultApprovalPolicy: draft.defaultApprovalPolicy
                )
            )
        }

        self.sortAndPersist()
    }

    func delete(workspaceID: UUID) {
        self.workspaces.removeAll(where: { $0.id == workspaceID })
        self.persistWorkspaces()
    }

    private func loadWorkspaces() {
        guard let data = self.defaults.data(forKey: self.workspacesKey),
              let decoded = try? JSONDecoder().decode([ProjectWorkspace].self, from: data)
        else {
            self.workspaces = []
            return
        }

        self.workspaces = decoded
        self.workspaces.sort(by: Self.compare)
    }

    private func sortAndPersist() {
        self.workspaces.sort(by: Self.compare)
        self.persistWorkspaces()
    }

    private func persistWorkspaces() {
        guard let data = try? JSONEncoder().encode(self.workspaces) else {
            self.defaults.removeObject(forKey: self.workspacesKey)
            return
        }
        self.defaults.set(data, forKey: self.workspacesKey)
    }

    private static func compare(lhs: ProjectWorkspace, rhs: ProjectWorkspace) -> Bool {
        if lhs.connectionID != rhs.connectionID {
            return lhs.connectionID.uuidString < rhs.connectionID.uuidString
        }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }
}

@MainActor
final class ThreadBookmarkStore: ObservableObject {
    @Published private(set) var bookmarks: [CodexThreadSummary] = []

    private let defaults: UserDefaults
    private let bookmarksKey = "codex.thread.bookmarks.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.load()
    }

    func threads(for workspaceID: UUID?) -> [CodexThreadSummary] {
        guard let workspaceID else { return [] }
        return self.bookmarks
            .filter { $0.workspaceID == workspaceID }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func upsert(summary: CodexThreadSummary) {
        if let index = self.bookmarks.firstIndex(where: {
            $0.threadID == summary.threadID && $0.workspaceID == summary.workspaceID
        }) {
            self.bookmarks[index] = summary
        } else {
            self.bookmarks.append(summary)
        }
        self.persist()
    }

    func replaceThreads(for workspaceID: UUID, connectionID: UUID, with summaries: [CodexThreadSummary]) {
        self.bookmarks.removeAll(where: { $0.workspaceID == workspaceID && $0.connectionID == connectionID })
        self.bookmarks.append(contentsOf: summaries)
        self.persist()
    }

    func remove(threadID: String, workspaceID: UUID) {
        self.bookmarks.removeAll(where: { $0.threadID == threadID && $0.workspaceID == workspaceID })
        self.persist()
    }

    private func load() {
        guard let data = self.defaults.data(forKey: self.bookmarksKey),
              let decoded = try? JSONDecoder().decode([CodexThreadSummary].self, from: data)
        else {
            self.bookmarks = []
            return
        }
        self.bookmarks = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(self.bookmarks) else {
            self.defaults.removeObject(forKey: self.bookmarksKey)
            return
        }
        self.defaults.set(data, forKey: self.bookmarksKey)
    }
}

enum AppRootTab: Hashable {
    case connections
    case projects
    case threads
    case fallbackTerminal
}

@MainActor
final class AppState: ObservableObject {
    @Published var selectedTab: AppRootTab = .threads
    @Published var selectedConnectionID: UUID?
    @Published var selectedWorkspaceID: UUID?

    let fallbackConnectionStore: ConnectionStore
    let remoteConnectionStore: RemoteConnectionStore
    let projectStore: ProjectStore
    let threadBookmarkStore: ThreadBookmarkStore
    let appServerClient: AppServerClient

    init(
        fallbackConnectionStore: ConnectionStore = ConnectionStore(),
        remoteConnectionStore: RemoteConnectionStore = RemoteConnectionStore(),
        projectStore: ProjectStore = ProjectStore(),
        threadBookmarkStore: ThreadBookmarkStore = ThreadBookmarkStore(),
        appServerClient: AppServerClient = AppServerClient()
    ) {
        self.fallbackConnectionStore = fallbackConnectionStore
        self.remoteConnectionStore = remoteConnectionStore
        self.projectStore = projectStore
        self.threadBookmarkStore = threadBookmarkStore
        self.appServerClient = appServerClient

        self.selectedConnectionID = remoteConnectionStore.connections.first?.id
        self.syncWorkspaceSelection()
    }

    var selectedConnection: RemoteConnection? {
        guard let selectedConnectionID else { return nil }
        return self.remoteConnectionStore.connections.first(where: { $0.id == selectedConnectionID })
    }

    var selectedWorkspace: ProjectWorkspace? {
        guard let selectedWorkspaceID else { return nil }
        return self.projectStore.workspaces.first(where: { $0.id == selectedWorkspaceID })
    }

    func selectConnection(_ connectionID: UUID?) {
        self.selectedConnectionID = connectionID
        self.syncWorkspaceSelection()
    }

    func selectWorkspace(_ workspaceID: UUID?) {
        self.selectedWorkspaceID = workspaceID
    }

    func refreshSelections() {
        if let selectedConnectionID,
           self.remoteConnectionStore.connections.contains(where: { $0.id == selectedConnectionID }) == false {
            self.selectedConnectionID = self.remoteConnectionStore.connections.first?.id
        }
        self.syncWorkspaceSelection()
    }

    private func syncWorkspaceSelection() {
        let candidates = self.projectStore.workspaces(for: self.selectedConnectionID)
        guard let selectedWorkspaceID else {
            self.selectedWorkspaceID = candidates.first?.id
            return
        }

        if candidates.contains(where: { $0.id == selectedWorkspaceID }) == false {
            self.selectedWorkspaceID = candidates.first?.id
        }
    }
}

enum JSONValue: Codable, Equatable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
            return
        }
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }
        if let value = try? container.decode(Int.self) {
            self = .number(Double(value))
            return
        }
        if let value = try? container.decode(Double.self) {
            self = .number(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
            return
        }
        if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
            return
        }

        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return String(value)
        case .bool(let value):
            return String(value)
        default:
            return nil
        }
    }

    var intValue: Int? {
        switch self {
        case .number(let value):
            return Int(value)
        case .string(let value):
            return Int(value)
        default:
            return nil
        }
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let value):
            return value
        case .string(let value):
            return Bool(value)
        default:
            return nil
        }
    }

    var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var arrayValue: [JSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    subscript(key: String) -> JSONValue? {
        self.objectValue?[key]
    }
}

struct JSONRPCErrorPayload: Codable, Equatable {
    let code: Int
    let message: String
    let data: JSONValue?
}

struct JSONRPCEnvelope: Codable, Equatable {
    let jsonrpc: String
    let id: JSONValue?
    let method: String?
    let params: JSONValue?
    let result: JSONValue?
    let error: JSONRPCErrorPayload?

    init(
        jsonrpc: String = "2.0",
        id: JSONValue? = nil,
        method: String? = nil,
        params: JSONValue? = nil,
        result: JSONValue? = nil,
        error: JSONRPCErrorPayload? = nil
    ) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.method = method
        self.params = params
        self.result = result
        self.error = error
    }
}

enum AppServerClientError: LocalizedError {
    case invalidURL
    case notConnected
    case timeout(method: String)
    case remote(code: Int, message: String)
    case incompatibleVersion(current: String, minimum: String)
    case malformedResponse
    case unsupportedMessage

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid app-server URL. Use ws:// or wss://."
        case .notConnected:
            return "Not connected to app-server."
        case .timeout(let method):
            return "Request timed out: \(method)"
        case .remote(let code, let message):
            return "Remote error [\(code)]: \(message)"
        case .incompatibleVersion(let current, let minimum):
            return "Codex CLI version \(current) is not supported. Required: \(minimum)+"
        case .malformedResponse:
            return "Malformed response from app-server."
        case .unsupportedMessage:
            return "Unsupported message from app-server."
        }
    }
}

actor AppServerMessageRouter {
    private var nextRequestID: Int = 1
    private var pending: [String: CheckedContinuation<JSONValue, Error>] = [:]

    func makeRequestID() -> Int {
        defer { self.nextRequestID += 1 }
        return self.nextRequestID
    }

    func storeContinuation(_ continuation: CheckedContinuation<JSONValue, Error>, for idKey: String) {
        self.pending[idKey] = continuation
    }

    func removeContinuation(for idKey: String) -> CheckedContinuation<JSONValue, Error>? {
        self.pending.removeValue(forKey: idKey)
    }

    func resolveResponse(id: JSONValue, result: JSONValue?, error: JSONRPCErrorPayload?) {
        guard let idKey = Self.idKey(from: id),
              let continuation = self.pending.removeValue(forKey: idKey)
        else {
            return
        }

        if let error {
            continuation.resume(throwing: AppServerClientError.remote(code: error.code, message: error.message))
            return
        }

        continuation.resume(returning: result ?? .null)
    }

    func failAll(with error: Error) {
        let continuations = self.pending.values
        self.pending.removeAll()
        continuations.forEach { continuation in
            continuation.resume(throwing: error)
        }
    }

    static func idKey(from value: JSONValue) -> String? {
        switch value {
        case .string(let id):
            return id
        case .number(let id):
            return String(Int(id))
        default:
            return nil
        }
    }
}

enum AppServerCommandApprovalDecision: String, CaseIterable, Identifiable {
    case accept
    case acceptForSession
    case decline
    case cancel

    var id: String { self.rawValue }
}

enum AppServerFileApprovalDecision: String, CaseIterable, Identifiable {
    case accept
    case acceptForSession
    case decline
    case cancel

    var id: String { self.rawValue }
}

struct AppServerUserInputQuestionOption: Equatable {
    let label: String
    let description: String
}

struct AppServerUserInputQuestion: Identifiable, Equatable {
    let id: String
    let prompt: String
    let options: [AppServerUserInputQuestionOption]
}

enum AppServerPendingRequestKind: Equatable {
    case commandApproval(command: String, cwd: String?, reason: String?)
    case fileChange(reason: String?)
    case userInput(questions: [AppServerUserInputQuestion])
    case unknown
}

struct AppServerPendingRequest: Identifiable, Equatable {
    let id = UUID()
    let rpcID: JSONValue
    let method: String
    let threadID: String
    let turnID: String
    let itemID: String
    let kind: AppServerPendingRequestKind

    var title: String {
        switch self.kind {
        case .commandApproval:
            return "Command Approval"
        case .fileChange:
            return "File Change Approval"
        case .userInput:
            return "User Input Required"
        case .unknown:
            return "Server Request"
        }
    }
}

struct RemoteThreadRecord: Equatable, Identifiable {
    let id: String
    let preview: String
    let updatedAt: Date
    let archived: Bool
    let cwd: String
}

enum AppServerErrorCategory: String {
    case authentication
    case connection
    case permission
    case compatibility
    case protocolError
    case unknown

    var title: String {
        switch self {
        case .authentication:
            return "Authentication"
        case .connection:
            return "Connection"
        case .permission:
            return "Permission"
        case .compatibility:
            return "Compatibility"
        case .protocolError:
            return "Protocol"
        case .unknown:
            return "Unknown"
        }
    }
}

struct AppServerDiagnostics: Equatable {
    var cliVersion: String = ""
    var authStatus: String = "unknown"
    var currentModel: String = ""
    var lastPingLatencyMS: Double?
    var lastCheckedAt: Date?
    var minimumRequiredVersion: String = "0.101.0"
}

@MainActor
final class AppServerClient: ObservableObject {
    static let minimumSupportedCLIVersion = "0.101.0"

    enum State: String {
        case disconnected
        case connecting
        case connected
    }

    @Published private(set) var state: State = .disconnected
    @Published private(set) var lastErrorMessage = ""
    @Published private(set) var connectedEndpoint = ""
    @Published private(set) var pendingRequests: [AppServerPendingRequest] = []
    @Published private(set) var transcriptByThread: [String: String] = [:]
    @Published private(set) var activeTurnIDByThread: [String: String] = [:]
    @Published private(set) var eventLog: [String] = []
    @Published private(set) var diagnostics = AppServerDiagnostics(
        minimumRequiredVersion: AppServerClient.minimumSupportedCLIVersion
    )

    private let session: URLSession
    private let router = AppServerMessageRouter()

    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?

    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 3
    private var autoReconnectEnabled = false
    private var lastConnection: RemoteConnection?

    private let requestTimeoutSeconds: TimeInterval = 30

    init(session: URLSession = .shared) {
        self.session = session
    }

    func connect(to connection: RemoteConnection) async throws {
        try await self.openConnection(to: connection, resetReconnectAttempts: true)
    }

    func disconnect() {
        self.autoReconnectEnabled = false
        self.reconnectTask?.cancel()
        self.reconnectTask = nil
        self.teardownConnection(closeCode: .goingAway)
        self.activeTurnIDByThread.removeAll()
        self.state = .disconnected
        self.connectedEndpoint = ""
    }

    func appendLocalEcho(_ text: String, to threadID: String) {
        let existing = self.transcriptByThread[threadID] ?? ""
        let prefix = existing.isEmpty ? "" : "\n"
        self.transcriptByThread[threadID] = existing + "\(prefix)> \(text)\n"
    }

    func clearThreadTranscript(_ threadID: String) {
        self.transcriptByThread.removeValue(forKey: threadID)
    }

    func activeTurnID(for threadID: String?) -> String? {
        guard let threadID else { return nil }
        return self.activeTurnIDByThread[threadID]
    }

    func runDiagnostics() async throws -> AppServerDiagnostics {
        guard self.state == .connected else {
            throw AppServerClientError.notConnected
        }

        let latency = try await self.measurePingLatency()
        self.diagnostics.lastPingLatencyMS = latency
        self.diagnostics.lastCheckedAt = Date()
        return self.diagnostics
    }

    func userFacingMessage(for error: Error) -> String {
        let category = Self.errorCategory(for: error)
        let baseMessage: String
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            baseMessage = description
        } else {
            baseMessage = error.localizedDescription
        }
        return "[\(category.title)] \(baseMessage)"
    }

    func threadList(archived: Bool? = nil, limit: Int = 100) async throws -> [RemoteThreadRecord] {
        var params: [String: JSONValue] = [
            "limit": .number(Double(limit))
        ]
        if let archived {
            params["archived"] = .bool(archived)
        }

        let result = try await self.request(method: "thread/list", params: .object(params))
        let payload: ThreadListResponsePayload = try self.decode(result, as: ThreadListResponsePayload.self)

        return payload.data.map { thread in
            RemoteThreadRecord(
                id: thread.id,
                preview: thread.preview,
                updatedAt: Date(timeIntervalSince1970: Double(thread.updatedAt)),
                archived: archived ?? false,
                cwd: thread.cwd
            )
        }
    }

    func threadRead(threadID: String) async throws -> CodexThreadDetail {
        let params: JSONValue = .object([
            "threadId": .string(threadID),
            "includeTurns": .bool(true),
        ])

        let result = try await self.request(method: "thread/read", params: params)
        let payload: ThreadReadResponsePayload = try self.decode(result, as: ThreadReadResponsePayload.self)
        let detail = self.convertThread(payload.thread)
        self.transcriptByThread[threadID] = Self.renderThread(detail)
        return detail
    }

    func threadStart(cwd: String, approvalPolicy: CodexApprovalPolicy, model: String?) async throws -> String {
        var params: [String: JSONValue] = [
            "cwd": .string(cwd),
            "approvalPolicy": .string(approvalPolicy.rawValue),
        ]

        if let model,
           !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            params["model"] = .string(model)
        }

        let result = try await self.request(method: "thread/start", params: .object(params))
        let payload: ThreadLifecycleResponsePayload = try self.decode(result, as: ThreadLifecycleResponsePayload.self)
        return payload.thread.id
    }

    func threadResume(threadID: String) async throws {
        let params: JSONValue = .object(["threadId": .string(threadID)])
        _ = try await self.request(method: "thread/resume", params: params)
    }

    func threadArchive(threadID: String, archived: Bool) async throws {
        let params: JSONValue = .object([
            "threadId": .string(threadID),
            "archived": .bool(archived),
        ])
        _ = try await self.request(method: "thread/archive", params: params)
    }

    @discardableResult
    func turnStart(threadID: String, inputText: String, model: String?) async throws -> String {
        var params: [String: JSONValue] = [
            "threadId": .string(threadID),
            "input": .array([
                .object([
                    "type": .string("text"),
                    "text": .string(inputText),
                ])
            ]),
        ]

        if let model,
           !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            params["model"] = .string(model)
        }

        let result = try await self.request(method: "turn/start", params: .object(params))
        let payload: TurnStartResponsePayload = try self.decode(result, as: TurnStartResponsePayload.self)
        self.activeTurnIDByThread[threadID] = payload.turn.id
        return payload.turn.id
    }

    func turnSteer(threadID: String, expectedTurnID: String, inputText: String) async throws {
        let params: JSONValue = .object([
            "threadId": .string(threadID),
            "expectedTurnId": .string(expectedTurnID),
            "input": .array([
                .object([
                    "type": .string("text"),
                    "text": .string(inputText),
                ])
            ]),
        ])
        _ = try await self.request(method: "turn/steer", params: params)
    }

    func turnInterrupt(threadID: String, turnID: String) async throws {
        let params: JSONValue = .object([
            "threadId": .string(threadID),
            "turnId": .string(turnID),
        ])
        _ = try await self.request(method: "turn/interrupt", params: params)
        if self.activeTurnIDByThread[threadID] == turnID {
            self.activeTurnIDByThread.removeValue(forKey: threadID)
        }
    }

    func respondCommandApproval(
        request: AppServerPendingRequest,
        decision: AppServerCommandApprovalDecision
    ) async throws {
        let result: JSONValue = .object(["decision": .string(decision.rawValue)])
        try await self.respond(to: request, result: result)
    }

    func respondFileChangeApproval(
        request: AppServerPendingRequest,
        decision: AppServerFileApprovalDecision
    ) async throws {
        let result: JSONValue = .object(["decision": .string(decision.rawValue)])
        try await self.respond(to: request, result: result)
    }

    func respondUserInput(
        request: AppServerPendingRequest,
        answers: [String: [String]]
    ) async throws {
        let answerObject = Dictionary(uniqueKeysWithValues: answers.map { key, values in
            (
                key,
                JSONValue.object([
                    "answers": .array(values.map { JSONValue.string($0) })
                ])
            )
        })

        let result: JSONValue = .object(["answers": .object(answerObject)])
        try await self.respond(to: request, result: result)
    }

    private func openConnection(to connection: RemoteConnection, resetReconnectAttempts: Bool) async throws {
        guard let url = URL(string: connection.appServerURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "ws" || scheme == "wss"
        else {
            throw AppServerClientError.invalidURL
        }

        self.reconnectTask?.cancel()
        self.teardownConnection(closeCode: .normalClosure)

        if resetReconnectAttempts {
            self.reconnectAttempts = 0
        }

        self.state = .connecting
        self.lastErrorMessage = ""
        self.autoReconnectEnabled = true
        self.lastConnection = connection
        self.connectedEndpoint = connection.appServerURL
        self.diagnostics = AppServerDiagnostics(
            minimumRequiredVersion: Self.minimumSupportedCLIVersion
        )

        let task = self.session.webSocketTask(with: url)
        self.webSocketTask = task
        task.resume()

        self.startReceiveLoop()
        self.startPingLoop()

        do {
            let initializeResult = try await self.request(
                method: "initialize",
                params: .object([
                    "clientInfo": .object([
                        "name": .string("CodexAppMobile"),
                        "version": .string("0.1.0")
                    ])
                ])
            )
            self.applyInitializeMetadata(from: initializeResult)
            if let cliVersion = self.nonEmptyOrNil(self.diagnostics.cliVersion),
               !Self.isVersion(cliVersion, atLeast: Self.minimumSupportedCLIVersion) {
                throw AppServerClientError.incompatibleVersion(
                    current: cliVersion,
                    minimum: Self.minimumSupportedCLIVersion
                )
            }
            self.state = .connected
            self.diagnostics.lastCheckedAt = Date()
            self.appendEvent("Connected: \(connection.name) @ \(connection.appServerURL)")
        } catch {
            self.lastErrorMessage = self.userFacingMessage(for: error)
            self.state = .disconnected
            self.connectedEndpoint = ""
            self.teardownConnection(closeCode: .normalClosure)
            throw error
        }
    }

    private func request(method: String, params: JSONValue?) async throws -> JSONValue {
        guard self.webSocketTask != nil else {
            throw AppServerClientError.notConnected
        }

        let requestID = await self.router.makeRequestID()
        let idValue: JSONValue = .number(Double(requestID))
        let idKey = String(requestID)
        let envelope = JSONRPCEnvelope(id: idValue, method: method, params: params)

        return try await withCheckedThrowingContinuation { continuation in
            Task { [weak self] in
                guard let self else {
                    continuation.resume(throwing: AppServerClientError.notConnected)
                    return
                }

                await self.router.storeContinuation(continuation, for: idKey)

                do {
                    try await self.sendEnvelope(envelope)
                } catch {
                    if let pending = await self.router.removeContinuation(for: idKey) {
                        pending.resume(throwing: error)
                    }
                    return
                }

                Task { [weak self] in
                    guard let self else { return }
                    let timeoutNanoseconds = UInt64(self.requestTimeoutSeconds * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                    if let pending = await self.router.removeContinuation(for: idKey) {
                        pending.resume(throwing: AppServerClientError.timeout(method: method))
                    }
                }
            }
        }
    }

    private func respond(to request: AppServerPendingRequest, result: JSONValue) async throws {
        try await self.sendEnvelope(
            JSONRPCEnvelope(
                id: request.rpcID,
                result: result
            )
        )
        self.pendingRequests.removeAll(where: { $0.id == request.id })
    }

    private func sendEnvelope(_ envelope: JSONRPCEnvelope) async throws {
        guard let webSocketTask = self.webSocketTask else {
            throw AppServerClientError.notConnected
        }

        let data = try JSONEncoder().encode(envelope)
        guard let message = String(data: data, encoding: .utf8) else {
            throw AppServerClientError.malformedResponse
        }

        try await webSocketTask.send(.string(message))
    }

    private func startReceiveLoop() {
        self.receiveTask?.cancel()
        self.receiveTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                guard let webSocketTask = self.webSocketTask else {
                    return
                }

                do {
                    let message = try await webSocketTask.receive()
                    try await self.handleIncoming(message)
                } catch {
                    if Task.isCancelled {
                        return
                    }
                    await self.handleSocketFailure(error)
                    return
                }
            }
        }
    }

    private func startPingLoop() {
        self.pingTask?.cancel()
        self.pingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                if Task.isCancelled {
                    return
                }
                guard let webSocketTask = self.webSocketTask else {
                    return
                }

                do {
                    let startedAt = Date()
                    try await webSocketTask.sendPingAsync()
                    self.diagnostics.lastPingLatencyMS = Date().timeIntervalSince(startedAt) * 1000
                    self.diagnostics.lastCheckedAt = Date()
                } catch {
                    await self.handleSocketFailure(error)
                    return
                }
            }
        }
    }

    private func handleIncoming(_ message: URLSessionWebSocketTask.Message) async throws {
        let data: Data
        switch message {
        case .data(let binaryData):
            data = binaryData
        case .string(let string):
            guard let encoded = string.data(using: .utf8) else {
                throw AppServerClientError.malformedResponse
            }
            data = encoded
        @unknown default:
            throw AppServerClientError.unsupportedMessage
        }

        let envelope = try JSONDecoder().decode(JSONRPCEnvelope.self, from: data)

        if let method = envelope.method {
            if let requestID = envelope.id {
                self.handleServerRequest(id: requestID, method: method, params: envelope.params)
            } else {
                self.handleNotification(method: method, params: envelope.params)
            }
            return
        }

        guard let responseID = envelope.id else {
            throw AppServerClientError.malformedResponse
        }

        await self.router.resolveResponse(id: responseID, result: envelope.result, error: envelope.error)
    }

    private func handleServerRequest(id: JSONValue, method: String, params: JSONValue?) {
        let parsed = self.parsePendingRequest(id: id, method: method, params: params)
        self.pendingRequests.append(parsed)
        self.appendEvent("Server request: \(method)")
    }

    private func handleNotification(method: String, params: JSONValue?) {
        let paramsObject = params?.objectValue ?? [:]

        switch method {
        case "item/agentMessage/delta", "item/commandExecution/outputDelta":
            guard let threadID = paramsObject["threadId"]?.stringValue,
                  let delta = paramsObject["delta"]?.stringValue
            else {
                return
            }
            let existing = self.transcriptByThread[threadID] ?? ""
            self.transcriptByThread[threadID] = existing + delta

        case "turn/started":
            if let threadID = paramsObject["threadId"]?.stringValue,
               let turn = paramsObject["turn"]?.objectValue,
               let turnID = turn["id"]?.stringValue {
                self.activeTurnIDByThread[threadID] = turnID
                self.appendEvent("Turn started for \(threadID)")
            }

        case "turn/completed":
            if let threadID = paramsObject["threadId"]?.stringValue,
               let turn = paramsObject["turn"]?.objectValue,
               let status = turn["status"]?.stringValue {
                self.appendEvent("Turn completed [\(status)] for \(threadID)")
                self.activeTurnIDByThread.removeValue(forKey: threadID)
            }

        case "thread/started":
            if let thread = paramsObject["thread"]?.objectValue,
               let threadID = thread["id"]?.stringValue {
                self.appendEvent("Thread started: \(threadID)")
            }

        case "error":
            if let message = paramsObject["message"]?.stringValue {
                self.lastErrorMessage = "[Protocol] \(message)"
            }

        default:
            self.appendEvent("Notification: \(method)")
        }
    }

    private func parsePendingRequest(id: JSONValue, method: String, params: JSONValue?) -> AppServerPendingRequest {
        let paramsObject = params?.objectValue ?? [:]
        let threadID = paramsObject["threadId"]?.stringValue ?? ""
        let turnID = paramsObject["turnId"]?.stringValue ?? ""
        let itemID = paramsObject["itemId"]?.stringValue ?? ""

        let kind: AppServerPendingRequestKind
        switch method {
        case "item/commandExecution/requestApproval":
            let command = paramsObject["command"]?.stringValue ?? ""
            let cwd = paramsObject["cwd"]?.stringValue
            let reason = paramsObject["reason"]?.stringValue
            kind = .commandApproval(command: command, cwd: cwd, reason: reason)

        case "item/fileChange/requestApproval":
            let reason = paramsObject["reason"]?.stringValue
            kind = .fileChange(reason: reason)

        case "item/tool/requestUserInput":
            let questions = (paramsObject["questions"]?.arrayValue ?? []).compactMap { rawQuestion -> AppServerUserInputQuestion? in
                guard let questionObject = rawQuestion.objectValue,
                      let questionID = questionObject["id"]?.stringValue
                else {
                    return nil
                }

                let prompt = questionObject["question"]?.stringValue
                    ?? questionObject["header"]?.stringValue
                    ?? "Input required"

                let options = (questionObject["options"]?.arrayValue ?? []).compactMap { rawOption -> AppServerUserInputQuestionOption? in
                    guard let optionObject = rawOption.objectValue,
                          let label = optionObject["label"]?.stringValue
                    else {
                        return nil
                    }
                    let description = optionObject["description"]?.stringValue ?? ""
                    return AppServerUserInputQuestionOption(label: label, description: description)
                }

                return AppServerUserInputQuestion(id: questionID, prompt: prompt, options: options)
            }
            kind = .userInput(questions: questions)

        default:
            kind = .unknown
        }

        return AppServerPendingRequest(
            rpcID: id,
            method: method,
            threadID: threadID,
            turnID: turnID,
            itemID: itemID,
            kind: kind
        )
    }

    private func handleSocketFailure(_ error: Error) async {
        self.lastErrorMessage = self.userFacingMessage(for: error)
        self.state = .disconnected
        self.connectedEndpoint = ""
        self.activeTurnIDByThread.removeAll()
        self.teardownConnection(closeCode: .abnormalClosure)

        guard self.autoReconnectEnabled,
              let connection = self.lastConnection
        else {
            return
        }

        guard self.reconnectAttempts < self.maxReconnectAttempts else {
            self.appendEvent("Reconnect attempts exhausted.")
            return
        }

        self.reconnectAttempts += 1
        let delaySeconds = pow(2.0, Double(self.reconnectAttempts - 1))
        self.appendEvent("Reconnect in \(Int(delaySeconds))s...")

        self.reconnectTask?.cancel()
        self.reconnectTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            if Task.isCancelled {
                return
            }

            do {
                try await self.openConnection(to: connection, resetReconnectAttempts: false)
            } catch {
                await self.handleSocketFailure(error)
            }
        }
    }

    private func teardownConnection(closeCode: URLSessionWebSocketTask.CloseCode) {
        self.receiveTask?.cancel()
        self.receiveTask = nil

        self.pingTask?.cancel()
        self.pingTask = nil

        self.webSocketTask?.cancel(with: closeCode, reason: nil)
        self.webSocketTask = nil
        self.pendingRequests.removeAll()

        Task {
            await self.router.failAll(with: AppServerClientError.notConnected)
        }
    }

    private func measurePingLatency() async throws -> Double {
        guard let webSocketTask = self.webSocketTask else {
            throw AppServerClientError.notConnected
        }

        let startedAt = Date()
        try await webSocketTask.sendPingAsync()
        return Date().timeIntervalSince(startedAt) * 1000
    }

    private func applyInitializeMetadata(from result: JSONValue) {
        guard let object = result.objectValue else {
            return
        }

        if let cliVersion = Self.findString(
            in: object,
            paths: [
                ["serverInfo", "version"],
                ["server", "version"],
                ["cli", "version"],
                ["version"],
            ]
        ) {
            self.diagnostics.cliVersion = cliVersion
        }

        if let authStatus = Self.findString(
            in: object,
            paths: [
                ["authStatus"],
                ["auth", "status"],
                ["session", "authStatus"],
                ["login", "status"],
            ]
        ) {
            self.diagnostics.authStatus = authStatus
        }

        if let model = Self.findString(
            in: object,
            paths: [
                ["currentModel"],
                ["model"],
                ["session", "model"],
                ["defaults", "model"],
            ]
        ) {
            self.diagnostics.currentModel = model
        }
    }

    private func nonEmptyOrNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func isVersion(_ version: String, atLeast minimum: String) -> Bool {
        let left = Self.versionComponents(version)
        let right = Self.versionComponents(minimum)
        let maxCount = max(left.count, right.count)

        for index in 0..<maxCount {
            let lhs = index < left.count ? left[index] : 0
            let rhs = index < right.count ? right[index] : 0
            if lhs == rhs {
                continue
            }
            return lhs > rhs
        }

        return true
    }

    private static func versionComponents(_ rawVersion: String) -> [Int] {
        let matches = rawVersion.matches(of: /(\d+)/)
        return matches.compactMap { Int($0.output.1) }
    }

    private static func findString(in object: [String: JSONValue], paths: [[String]]) -> String? {
        for path in paths {
            guard let value = Self.value(at: path, in: object),
                  let stringValue = value.stringValue?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !stringValue.isEmpty
            else {
                continue
            }
            return stringValue
        }
        return nil
    }

    private static func value(at path: [String], in object: [String: JSONValue]) -> JSONValue? {
        guard let first = path.first else { return nil }
        var cursor = object[first]
        for key in path.dropFirst() {
            guard let next = cursor?.objectValue?[key] else {
                return nil
            }
            cursor = next
        }
        return cursor
    }

    private static func errorCategory(for error: Error) -> AppServerErrorCategory {
        if let appServerError = error as? AppServerClientError {
            switch appServerError {
            case .incompatibleVersion:
                return .compatibility
            case .invalidURL, .notConnected, .timeout:
                return .connection
            case .malformedResponse, .unsupportedMessage:
                return .protocolError
            case .remote(let code, let message):
                return Self.errorCategoryFromRemote(code: code, message: message)
            }
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .userAuthenticationRequired:
                return .authentication
            default:
                return .connection
            }
        }

        let message = error.localizedDescription.lowercased()
        if message.contains("auth") || message.contains("token") || message.contains("login") {
            return .authentication
        }
        if message.contains("forbidden") || message.contains("permission") || message.contains("denied") {
            return .permission
        }
        if message.contains("version") || message.contains("unsupported") {
            return .compatibility
        }
        if message.contains("timeout") || message.contains("network") || message.contains("connection") {
            return .connection
        }
        return .unknown
    }

    private static func errorCategoryFromRemote(code: Int, message: String) -> AppServerErrorCategory {
        let lowered = message.lowercased()

        if code == 401 || code == 403 || lowered.contains("auth") || lowered.contains("token") || lowered.contains("login") {
            return .authentication
        }
        if lowered.contains("permission") || lowered.contains("denied") || lowered.contains("forbidden") {
            return .permission
        }
        if lowered.contains("version") || lowered.contains("unsupported") {
            return .compatibility
        }
        if code == -32700 || code == -32600 || code == -32601 || code == -32602 || code == -32603 {
            return .protocolError
        }
        return .unknown
    }

    private func decode<T: Decodable>(_ value: JSONValue, as type: T.Type) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(type, from: data)
    }

    private func convertThread(_ thread: ThreadReadThreadPayload) -> CodexThreadDetail {
        let turns = thread.turns.map { turn in
            let items = turn.items.map { item -> CodexTurnItem in
                switch item.type {
                case "userMessage":
                    let texts = (item.content ?? []).compactMap { input in
                        if input.type == "text" {
                            return input.text
                        }
                        if input.type == "image" {
                            return "[image]"
                        }
                        if input.type == "localImage" {
                            return "[localImage] \(input.path ?? "")"
                        }
                        if input.type == "skill" || input.type == "mention" {
                            return "[\(input.type)] \(input.name ?? input.path ?? "")"
                        }
                        return nil
                    }
                    let message = texts.joined(separator: "\n")
                    return .userMessage(id: item.id, text: message)

                case "agentMessage":
                    return .agentMessage(id: item.id, text: item.text ?? "")

                case "plan":
                    return .plan(id: item.id, text: item.text ?? "")

                case "reasoning":
                    let summaryText = (item.summary ?? []).compactMap { summaryPart in
                        summaryPart["text"]?.stringValue ?? summaryPart.stringValue
                    }.joined(separator: "\n")
                    return .reasoning(id: item.id, text: summaryText)

                case "commandExecution":
                    return .commandExecution(
                        id: item.id,
                        command: item.command ?? "",
                        status: item.status ?? "unknown",
                        output: item.aggregatedOutput
                    )

                case "fileChange":
                    return .fileChange(
                        id: item.id,
                        status: item.status ?? "unknown",
                        changedFiles: item.changes?.count ?? 0
                    )

                default:
                    return .other(id: item.id, type: item.type)
                }
            }

            return CodexTurn(id: turn.id, status: turn.status, items: items)
        }

        return CodexThreadDetail(threadID: thread.id, turns: turns)
    }

    private static func renderThread(_ detail: CodexThreadDetail) -> String {
        var lines: [String] = []
        for turn in detail.turns {
            lines.append("=== Turn \(turn.id) [\(turn.status)] ===")
            for item in turn.items {
                switch item {
                case .userMessage(_, let text):
                    lines.append("User: \(text)")
                case .agentMessage(_, let text):
                    lines.append("Assistant: \(text)")
                case .plan(_, let text):
                    lines.append("Plan: \(text)")
                case .reasoning(_, let text):
                    if !text.isEmpty {
                        lines.append("Reasoning: \(text)")
                    }
                case .commandExecution(_, let command, let status, let output):
                    lines.append("$ \(command) [\(status)]")
                    if let output,
                       !output.isEmpty {
                        lines.append(output)
                    }
                case .fileChange(_, let status, let changedFiles):
                    lines.append("File change [\(status)] files=\(changedFiles)")
                case .other(_, let type):
                    lines.append("Item: \(type)")
                }
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func appendEvent(_ message: String) {
        self.eventLog.append(message)
        if self.eventLog.count > 200 {
            self.eventLog.removeFirst(self.eventLog.count - 200)
        }
    }
}

private extension URLSessionWebSocketTask {
    func sendPingAsync() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.sendPing { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

private struct ThreadListResponsePayload: Decodable {
    let data: [ThreadListEntryPayload]
}

private struct ThreadListEntryPayload: Decodable {
    let id: String
    let preview: String
    let updatedAt: Int
    let cwd: String
}

private struct ThreadLifecycleResponsePayload: Decodable {
    let thread: ThreadIDPayload
}

private struct ThreadIDPayload: Decodable {
    let id: String
}

private struct TurnStartResponsePayload: Decodable {
    let turn: TurnIDPayload
}

private struct TurnIDPayload: Decodable {
    let id: String
}

private struct ThreadReadResponsePayload: Decodable {
    let thread: ThreadReadThreadPayload
}

private struct ThreadReadThreadPayload: Decodable {
    let id: String
    let turns: [ThreadReadTurnPayload]
}

private struct ThreadReadTurnPayload: Decodable {
    let id: String
    let status: String
    let items: [ThreadReadItemPayload]
}

private struct ThreadReadItemPayload: Decodable {
    let id: String
    let type: String
    let text: String?
    let status: String?
    let command: String?
    let aggregatedOutput: String?
    let changes: [ThreadReadFileChangePayload]?
    let content: [ThreadReadUserInputPayload]?
    let summary: [JSONValue]?
}

private struct ThreadReadFileChangePayload: Decodable {
    let path: String?
}

private struct ThreadReadUserInputPayload: Decodable {
    let type: String
    let text: String?
    let path: String?
    let name: String?
}

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView(selection: self.$appState.selectedTab) {
            ConnectionsTabView()
                .tabItem {
                    Label("Connections", systemImage: "network")
                }
                .tag(AppRootTab.connections)

            ProjectsTabView()
                .tabItem {
                    Label("Projects", systemImage: "folder")
                }
                .tag(AppRootTab.projects)

            ThreadsTabView()
                .tabItem {
                    Label("Threads", systemImage: "message")
                }
                .tag(AppRootTab.threads)

            FallbackTerminalView()
                .tabItem {
                    Label("Fallback", systemImage: "terminal")
                }
                .tag(AppRootTab.fallbackTerminal)
        }
    }
}

struct ConnectionsTabView: View {
    @EnvironmentObject private var appState: AppState

    @State private var isPresentingEditor = false
    @State private var editingConnection: RemoteConnection?
    @State private var editingPassword = ""

    var body: some View {
        NavigationStack {
            Group {
                if self.appState.remoteConnectionStore.connections.isEmpty {
                    ContentUnavailableView(
                        "No Remote Connections",
                        systemImage: "network",
                        description: Text("Tap + to add your first app-server endpoint.")
                    )
                } else {
                    List {
                        ForEach(self.appState.remoteConnectionStore.connections) { connection in
                            Button {
                                self.appState.selectConnection(connection.id)
                            } label: {
                                HStack(alignment: .center, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(connection.name)
                                            .font(.headline)
                                        Text("\(connection.username)@\(connection.host):\(connection.sshPort)")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        Text(connection.appServerURL)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                    }

                                    Spacer(minLength: 8)

                                    if self.appState.selectedConnectionID == connection.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Delete", role: .destructive) {
                                    self.appState.remoteConnectionStore.delete(connectionID: connection.id)
                                    self.appState.refreshSelections()
                                }

                                Button("Edit") {
                                    self.editingConnection = connection
                                    self.editingPassword = self.appState.remoteConnectionStore.password(for: connection.id)
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
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fallback") {
                        self.appState.selectedTab = .fallbackTerminal
                    }
                    .codexActionButtonStyle()
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        self.editingConnection = nil
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
            RemoteConnectionEditorView(
                connection: self.editingConnection,
                initialPassword: self.editingPassword
            ) { draft in
                self.appState.remoteConnectionStore.upsert(connectionID: self.editingConnection?.id, draft: draft)
                self.appState.refreshSelections()
            }
        }
    }
}

struct RemoteConnectionEditorView: View {
    let connection: RemoteConnection?
    let initialPassword: String
    let onSave: (RemoteConnectionDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var host: String
    @State private var sshPortText: String
    @State private var username: String
    @State private var appServerURL: String
    @State private var password: String

    @State private var preferredTransport: TransportKind
    @State private var authMode: ConnectionAuthMode

    init(connection: RemoteConnection?, initialPassword: String, onSave: @escaping (RemoteConnectionDraft) -> Void) {
        self.connection = connection
        self.initialPassword = initialPassword
        self.onSave = onSave

        _name = State(initialValue: connection?.name ?? "")
        _host = State(initialValue: connection?.host ?? "")
        _sshPortText = State(initialValue: String(connection?.sshPort ?? 22))
        _username = State(initialValue: connection?.username ?? "")
        _appServerURL = State(initialValue: connection?.appServerURL ?? "")
        _password = State(initialValue: initialPassword)
        _preferredTransport = State(initialValue: connection?.preferredTransport ?? .appServerWS)
        _authMode = State(initialValue: connection?.authMode ?? .remotePCManaged)
    }

    private var parsedPort: Int {
        Int(self.sshPortText) ?? 22
    }

    private var draft: RemoteConnectionDraft {
        RemoteConnectionDraft(
            name: self.name,
            host: self.host,
            sshPort: self.parsedPort,
            username: self.username,
            appServerURL: self.appServerURL,
            preferredTransport: self.preferredTransport,
            authMode: self.authMode,
            password: self.password
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic") {
                    TextField("Name", text: self.$name)
                    TextField("Host", text: self.$host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    TextField("SSH Port", text: self.$sshPortText)
                        .keyboardType(.numberPad)
                    TextField("Username", text: self.$username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                }

                Section("App Server") {
                    TextField("ws://100.x.x.x:8080", text: self.$appServerURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .textContentType(.URL)

                    Picker("Transport", selection: self.$preferredTransport) {
                        ForEach(TransportKind.allCases) { transport in
                            Text(transport.displayName).tag(transport)
                        }
                    }

                    Picker("Auth", selection: self.$authMode) {
                        ForEach(ConnectionAuthMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                }

                Section("SSH Fallback") {
                    SecureField("Password (optional)", text: self.$password)
                }

                if self.connection == nil {
                    Section {
                        Button("Use host to generate app-server URL") {
                            let normalizedHost = self.host.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !normalizedHost.isEmpty else { return }
                            self.appServerURL = RemoteConnection.defaultAppServerURL(host: normalizedHost)
                        }
                    }
                }
            }
            .navigationTitle(self.connection == nil ? "New Connection" : "Edit Connection")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        self.dismiss()
                    }
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

struct ProjectsTabView: View {
    @EnvironmentObject private var appState: AppState

    @State private var isPresentingEditor = false
    @State private var editingWorkspace: ProjectWorkspace?

    private var selectedConnection: RemoteConnection? {
        self.appState.selectedConnection
    }

    private var workspaces: [ProjectWorkspace] {
        self.appState.projectStore.workspaces(for: self.appState.selectedConnectionID)
    }

    var body: some View {
        NavigationStack {
            Group {
                if self.appState.remoteConnectionStore.connections.isEmpty {
                    ContentUnavailableView(
                        "No Connections",
                        systemImage: "network.slash",
                        description: Text("Create a connection first from the Connections tab.")
                    )
                } else if self.selectedConnection == nil {
                    ContentUnavailableView(
                        "Select Connection",
                        systemImage: "network",
                        description: Text("Choose a connection to manage project paths.")
                    )
                } else {
                    List {
                        Section {
                            Picker("Connection", selection: Binding(
                                get: { self.appState.selectedConnectionID },
                                set: { self.appState.selectConnection($0) }
                            )) {
                                ForEach(self.appState.remoteConnectionStore.connections) { connection in
                                    Text(connection.name).tag(Optional(connection.id))
                                }
                            }
                        }

                        if self.workspaces.isEmpty {
                            Section {
                                Text("No projects for this connection.")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            ForEach(self.workspaces) { workspace in
                                Button {
                                    self.appState.selectWorkspace(workspace.id)
                                } label: {
                                    HStack(alignment: .center, spacing: 8) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(workspace.displayName)
                                                .font(.headline)
                                            Text(workspace.remotePath)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .textSelection(.enabled)
                                            if !workspace.defaultModel.isEmpty {
                                                Text("model: \(workspace.defaultModel)")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }

                                        Spacer(minLength: 8)

                                        if self.appState.selectedWorkspaceID == workspace.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.green)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button("Delete", role: .destructive) {
                                        self.appState.projectStore.delete(workspaceID: workspace.id)
                                        self.appState.refreshSelections()
                                    }

                                    Button("Edit") {
                                        self.editingWorkspace = workspace
                                        self.isPresentingEditor = true
                                    }
                                    .tint(.orange)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Projects")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        self.editingWorkspace = nil
                        self.isPresentingEditor = true
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .disabled(self.selectedConnection == nil)
                    .codexActionButtonStyle()
                }
            }
        }
        .sheet(isPresented: self.$isPresentingEditor) {
            if let selectedConnection {
                ProjectEditorView(workspace: self.editingWorkspace) { draft in
                    self.appState.projectStore.upsert(
                        workspaceID: self.editingWorkspace?.id,
                        connectionID: selectedConnection.id,
                        draft: draft
                    )
                    self.appState.refreshSelections()
                }
            }
        }
    }
}

struct ProjectEditorView: View {
    let workspace: ProjectWorkspace?
    let onSave: (ProjectWorkspaceDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var remotePath: String
    @State private var defaultModel: String
    @State private var defaultApprovalPolicy: CodexApprovalPolicy

    init(workspace: ProjectWorkspace?, onSave: @escaping (ProjectWorkspaceDraft) -> Void) {
        self.workspace = workspace
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
                    Button("Cancel") {
                        self.dismiss()
                    }
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

struct ThreadsTabView: View {
    @EnvironmentObject private var appState: AppState

    @State private var selectedThreadID: String?
    @State private var prompt = ""
    @State private var localErrorMessage = ""
    @State private var isRefreshingThreads = false
    @State private var showArchived = false
    @State private var isPresentingDiagnostics = false
    @State private var activePendingRequest: AppServerPendingRequest?

    private var selectedConnection: RemoteConnection? {
        self.appState.selectedConnection
    }

    private var selectedWorkspace: ProjectWorkspace? {
        self.appState.selectedWorkspace
    }

    private var threads: [CodexThreadSummary] {
        self.appState.threadBookmarkStore.threads(for: self.appState.selectedWorkspaceID)
    }

    private var selectedThreadTranscript: String {
        guard let selectedThreadID else { return "" }
        return self.appState.appServerClient.transcriptByThread[selectedThreadID] ?? ""
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Status") {
                    if let selectedConnection {
                        Text("Connection: \(selectedConnection.name)")
                    } else {
                        Text("Connection: not selected")
                            .foregroundStyle(.secondary)
                    }

                    if let selectedWorkspace {
                        Text("Project: \(selectedWorkspace.displayName)")
                    } else {
                        Text("Project: not selected")
                            .foregroundStyle(.secondary)
                    }

                    Text("State: \(self.appState.appServerClient.state.rawValue)")

                    if !self.appState.appServerClient.connectedEndpoint.isEmpty {
                        Text("Endpoint: \(self.appState.appServerClient.connectedEndpoint)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    if !self.appState.appServerClient.diagnostics.cliVersion.isEmpty {
                        Text("CLI: \(self.appState.appServerClient.diagnostics.cliVersion)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let latency = self.appState.appServerClient.diagnostics.lastPingLatencyMS {
                        Text("Ping: \(latency.formatted(.number.precision(.fractionLength(0)))) ms")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !self.appState.appServerClient.lastErrorMessage.isEmpty {
                        Text(self.appState.appServerClient.lastErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if !self.localErrorMessage.isEmpty {
                        Text(self.localErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    HStack {
                        Button("Connect") {
                            self.connect()
                        }
                        .disabled(self.selectedConnection == nil || self.appState.appServerClient.state == .connected)
                        .codexActionButtonStyle()

                        Button("Disconnect") {
                            self.appState.appServerClient.disconnect()
                        }
                        .disabled(self.appState.appServerClient.state == .disconnected)
                        .codexActionButtonStyle()

                        Button("Refresh") {
                            self.refreshThreads()
                        }
                        .disabled(self.selectedConnection == nil || self.selectedWorkspace == nil || self.isRefreshingThreads)
                        .codexActionButtonStyle()
                    }

                    Toggle("Show Archived", isOn: self.$showArchived)

                    HStack {
                        Button("Diagnostics") {
                            self.isPresentingDiagnostics = true
                        }
                        .codexActionButtonStyle()

                        Button("Open Fallback Terminal") {
                            self.appState.selectedTab = .fallbackTerminal
                        }
                        .codexActionButtonStyle()
                    }
                }

                Section("Threads") {
                    if self.threads.isEmpty {
                        Text("No threads for selected project.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(self.threads) { summary in
                            Button {
                                self.selectedThreadID = summary.threadID
                                self.loadThread(summary.threadID)
                            } label: {
                                HStack(alignment: .center, spacing: 8) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(summary.preview.isEmpty ? "(empty preview)" : summary.preview)
                                            .font(.subheadline)
                                            .lineLimit(2)
                                        Text(summary.threadID)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text(summary.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer(minLength: 8)

                                    if self.selectedThreadID == summary.threadID {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(self.showArchived ? "Unarchive" : "Archive") {
                                    self.archiveThread(summary: summary, archived: !self.showArchived)
                                }
                                .tint(self.showArchived ? .green : .blue)

                                Button("Delete", role: .destructive) {
                                    self.appState.threadBookmarkStore.remove(
                                        threadID: summary.threadID,
                                        workspaceID: summary.workspaceID
                                    )
                                    if self.selectedThreadID == summary.threadID {
                                        self.selectedThreadID = nil
                                    }
                                }
                            }
                        }
                    }
                }

                Section("Prompt") {
                    TextField("Send prompt", text: self.$prompt, axis: .vertical)
                        .lineLimit(1...5)
                        .textInputAutocapitalization(.sentences)

                    HStack {
                        Button("Send") {
                            self.sendPrompt(forceNewThread: false)
                        }
                        .disabled(self.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .codexActionButtonStyle()

                        Button("New Thread + Send") {
                            self.sendPrompt(forceNewThread: true)
                        }
                        .disabled(self.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .codexActionButtonStyle()

                        Button("Interrupt") {
                            self.interruptActiveTurn()
                        }
                        .disabled(
                            self.appState.appServerClient.activeTurnID(for: self.selectedThreadID) == nil
                        )
                        .codexActionButtonStyle()
                    }
                }

                Section("Pending Actions") {
                    if self.appState.appServerClient.pendingRequests.isEmpty {
                        Text("No pending approvals.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(self.appState.appServerClient.pendingRequests) { request in
                            Button {
                                self.activePendingRequest = request
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(request.title)
                                        .font(.subheadline)
                                    Text(request.method)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if !request.threadID.isEmpty {
                                        Text("thread: \(request.threadID)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Transcript") {
                    if let selectedThreadID,
                       !selectedThreadID.isEmpty {
                        Text(self.selectedThreadTranscript.isEmpty ? "No output yet." : self.selectedThreadTranscript)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Select thread to view output.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Threads")
        }
        .onChange(of: self.showArchived) {
            self.refreshThreads()
        }
        .sheet(isPresented: self.$isPresentingDiagnostics) {
            ConnectionDiagnosticsView()
                .environmentObject(self.appState)
        }
        .sheet(item: self.$activePendingRequest) { request in
            PendingRequestSheet(request: request)
                .environmentObject(self.appState)
        }
    }

    private func connect() {
        guard let selectedConnection else {
            self.localErrorMessage = "Select a connection first."
            return
        }

        self.localErrorMessage = ""
        Task {
            do {
                try await self.appState.appServerClient.connect(to: selectedConnection)
            } catch {
                self.localErrorMessage = self.appState.appServerClient.userFacingMessage(for: error)
            }
        }
    }

    private func refreshThreads() {
        guard let selectedConnection else {
            self.localErrorMessage = "Select a connection first."
            return
        }
        guard let selectedWorkspace else {
            self.localErrorMessage = "Select a project first."
            return
        }

        self.localErrorMessage = ""
        self.isRefreshingThreads = true

        Task {
            defer {
                self.isRefreshingThreads = false
            }

            do {
                if self.appState.appServerClient.state != .connected {
                    try await self.appState.appServerClient.connect(to: selectedConnection)
                }

                let fetched = try await self.appState.appServerClient.threadList(
                    archived: self.showArchived,
                    limit: 100
                )
                let scoped = fetched.filter { $0.cwd == selectedWorkspace.remotePath }

                let summaries = scoped.map { thread in
                    CodexThreadSummary(
                        threadID: thread.id,
                        connectionID: selectedConnection.id,
                        workspaceID: selectedWorkspace.id,
                        preview: thread.preview,
                        updatedAt: thread.updatedAt,
                        archived: thread.archived,
                        cwd: thread.cwd
                    )
                }

                self.appState.threadBookmarkStore.replaceThreads(
                    for: selectedWorkspace.id,
                    connectionID: selectedConnection.id,
                    with: summaries
                )

                if self.selectedThreadID == nil {
                    self.selectedThreadID = summaries.first?.threadID
                }
            } catch {
                self.localErrorMessage = self.appState.appServerClient.userFacingMessage(for: error)
            }
        }
    }

    private func sendPrompt(forceNewThread: Bool) {
        let trimmedPrompt = self.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            return
        }

        guard let selectedConnection else {
            self.localErrorMessage = "Select a connection first."
            return
        }

        guard let selectedWorkspace else {
            self.localErrorMessage = "Select a project first."
            return
        }

        self.localErrorMessage = ""

        Task {
            do {
                if self.appState.appServerClient.state != .connected {
                    try await self.appState.appServerClient.connect(to: selectedConnection)
                }

                var threadID = forceNewThread ? nil : self.selectedThreadID

                if threadID == nil {
                    let createdThreadID = try await self.appState.appServerClient.threadStart(
                        cwd: selectedWorkspace.remotePath,
                        approvalPolicy: selectedWorkspace.defaultApprovalPolicy,
                        model: selectedWorkspace.defaultModel
                    )
                    threadID = createdThreadID
                    self.selectedThreadID = createdThreadID
                }

                guard let threadID else {
                    self.localErrorMessage = "Failed to resolve thread."
                    return
                }

                self.appState.appServerClient.appendLocalEcho(trimmedPrompt, to: threadID)
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
                        model: selectedWorkspace.defaultModel
                    )
                }

                self.appState.threadBookmarkStore.upsert(
                    summary: CodexThreadSummary(
                        threadID: threadID,
                        connectionID: selectedConnection.id,
                        workspaceID: selectedWorkspace.id,
                        preview: trimmedPrompt,
                        updatedAt: Date(),
                        archived: false,
                        cwd: selectedWorkspace.remotePath
                    )
                )

                self.prompt = ""
            } catch {
                self.localErrorMessage = self.appState.appServerClient.userFacingMessage(for: error)
            }
        }
    }

    private func loadThread(_ threadID: String) {
        Task {
            do {
                _ = try await self.appState.appServerClient.threadRead(threadID: threadID)
            } catch {
                self.localErrorMessage = self.appState.appServerClient.userFacingMessage(for: error)
            }
        }
    }

    private func interruptActiveTurn() {
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
        guard let selectedConnection else {
            self.localErrorMessage = "Select a connection first."
            return
        }

        Task {
            do {
                if self.appState.appServerClient.state != .connected {
                    try await self.appState.appServerClient.connect(to: selectedConnection)
                }

                try await self.appState.appServerClient.threadArchive(
                    threadID: summary.threadID,
                    archived: archived
                )

                if archived {
                    self.appState.threadBookmarkStore.remove(
                        threadID: summary.threadID,
                        workspaceID: summary.workspaceID
                    )
                    if self.selectedThreadID == summary.threadID {
                        self.selectedThreadID = nil
                    }
                } else {
                    var restored = summary
                    restored.archived = false
                    restored.updatedAt = Date()
                    self.appState.threadBookmarkStore.upsert(summary: restored)
                }

                self.refreshThreads()
            } catch {
                self.localErrorMessage = self.appState.appServerClient.userFacingMessage(for: error)
            }
        }
    }
}

struct ConnectionDiagnosticsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var errorMessage = ""

    private var diagnostics: AppServerDiagnostics {
        self.appState.appServerClient.diagnostics
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    Text("State: \(self.appState.appServerClient.state.rawValue)")
                    if !self.appState.appServerClient.connectedEndpoint.isEmpty {
                        Text(self.appState.appServerClient.connectedEndpoint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    if let checkedAt = self.diagnostics.lastCheckedAt {
                        Text("Last check: \(checkedAt.formatted(date: .abbreviated, time: .standard))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Codex CLI") {
                    Text("CLI version: \(self.diagnostics.cliVersion.isEmpty ? "unknown" : self.diagnostics.cliVersion)")
                    Text("Required >= \(self.diagnostics.minimumRequiredVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Auth status: \(self.diagnostics.authStatus)")
                    Text("Current model: \(self.diagnostics.currentModel.isEmpty ? "unknown" : self.diagnostics.currentModel)")
                }

                Section("Health") {
                    if let latency = self.diagnostics.lastPingLatencyMS {
                        Text("Ping latency: \(latency.formatted(.number.precision(.fractionLength(0)))) ms")
                    } else {
                        Text("Ping latency: unknown")
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
            .navigationTitle("Diagnostics")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        self.dismiss()
                    }
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
                    Button("Close") {
                        self.dismiss()
                    }
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
