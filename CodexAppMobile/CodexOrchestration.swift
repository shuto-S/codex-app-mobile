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

struct RemoteHost: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var host: String
    var sshPort: Int
    var username: String
    var appServerURL: String
    var preferredTransport: TransportKind
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        sshPort: Int,
        username: String,
        appServerURL: String,
        preferredTransport: TransportKind = .ssh,
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
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static func defaultAppServerURL(host: String, port: Int = 8080) -> String {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        return "ws://\(normalizedHost):\(port)"
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case host
        case sshPort
        case username
        case appServerURL
        case preferredTransport
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decode(String.self, forKey: .name)
        self.host = try container.decode(String.self, forKey: .host)
        self.sshPort = try container.decodeIfPresent(Int.self, forKey: .sshPort) ?? 22
        self.username = try container.decode(String.self, forKey: .username)
        self.appServerURL = try container.decodeIfPresent(String.self, forKey: .appServerURL)
            ?? Self.defaultAppServerURL(host: self.host)
        self.preferredTransport = try container.decodeIfPresent(TransportKind.self, forKey: .preferredTransport) ?? .ssh
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.id, forKey: .id)
        try container.encode(self.name, forKey: .name)
        try container.encode(self.host, forKey: .host)
        try container.encode(self.sshPort, forKey: .sshPort)
        try container.encode(self.username, forKey: .username)
        try container.encode(self.appServerURL, forKey: .appServerURL)
        try container.encode(self.preferredTransport, forKey: .preferredTransport)
        try container.encode(self.createdAt, forKey: .createdAt)
        try container.encode(self.updatedAt, forKey: .updatedAt)
    }
}

struct RemoteHostDraft {
    var name: String
    var host: String
    var sshPort: Int
    var username: String
    var appServerHost: String
    var appServerPort: Int
    var preferredTransport: TransportKind
    var password: String

    static let empty = RemoteHostDraft(
        name: "",
        host: "",
        sshPort: 22,
        username: "",
        appServerHost: "",
        appServerPort: 8080,
        preferredTransport: .ssh,
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
              (1...65535).contains(self.appServerPort)
        else {
            return false
        }

        let trimmedAppServerHost = self.appServerHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedAppServerHost.contains("://") {
            return false
        }

        let endpointHost = trimmedAppServerHost.isEmpty ? trimmedHost : trimmedAppServerHost
        let endpoint = RemoteHost.defaultAppServerURL(host: endpointHost, port: self.appServerPort)
        guard let url = URL(string: endpoint),
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
        appServerHost: String,
        appServerPort: Int,
        preferredTransport: TransportKind,
        password: String
    ) {
        self.name = name
        self.host = host
        self.sshPort = sshPort
        self.username = username
        self.appServerHost = appServerHost
        self.appServerPort = appServerPort
        self.preferredTransport = preferredTransport
        self.password = password
    }

    init(host: RemoteHost, password: String) {
        self.name = host.name
        self.host = host.host
        self.sshPort = host.sshPort
        self.username = host.username
        if let components = URLComponents(string: host.appServerURL),
           let endpointHost = components.host {
            self.appServerHost = endpointHost == host.host ? "" : endpointHost
            self.appServerPort = components.port ?? 8080
        } else {
            self.appServerHost = ""
            self.appServerPort = 8080
        }
        self.preferredTransport = host.preferredTransport
        self.password = password
    }
}

struct ProjectWorkspace: Identifiable, Codable, Equatable {
    let id: UUID
    var hostID: UUID
    var name: String
    var remotePath: String
    var defaultModel: String
    var defaultApprovalPolicy: CodexApprovalPolicy
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        hostID: UUID,
        name: String,
        remotePath: String,
        defaultModel: String = "",
        defaultApprovalPolicy: CodexApprovalPolicy = .onRequest,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.hostID = hostID
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

    private enum CodingKeys: String, CodingKey {
        case id
        case hostID
        case connectionID
        case name
        case remotePath
        case defaultModel
        case defaultApprovalPolicy
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        if let hostID = try container.decodeIfPresent(UUID.self, forKey: .hostID) {
            self.hostID = hostID
        } else {
            self.hostID = try container.decode(UUID.self, forKey: .connectionID)
        }
        self.name = try container.decode(String.self, forKey: .name)
        self.remotePath = try container.decode(String.self, forKey: .remotePath)
        self.defaultModel = try container.decode(String.self, forKey: .defaultModel)
        self.defaultApprovalPolicy = try container.decode(CodexApprovalPolicy.self, forKey: .defaultApprovalPolicy)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.id, forKey: .id)
        try container.encode(self.hostID, forKey: .hostID)
        try container.encode(self.name, forKey: .name)
        try container.encode(self.remotePath, forKey: .remotePath)
        try container.encode(self.defaultModel, forKey: .defaultModel)
        try container.encode(self.defaultApprovalPolicy, forKey: .defaultApprovalPolicy)
        try container.encode(self.createdAt, forKey: .createdAt)
        try container.encode(self.updatedAt, forKey: .updatedAt)
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
    var hostID: UUID
    var workspaceID: UUID
    var preview: String
    var updatedAt: Date
    var archived: Bool
    var cwd: String

    private enum CodingKeys: String, CodingKey {
        case threadID
        case hostID
        case connectionID
        case workspaceID
        case preview
        case updatedAt
        case archived
        case cwd
    }

    init(
        threadID: String,
        hostID: UUID,
        workspaceID: UUID,
        preview: String,
        updatedAt: Date,
        archived: Bool,
        cwd: String
    ) {
        self.threadID = threadID
        self.hostID = hostID
        self.workspaceID = workspaceID
        self.preview = preview
        self.updatedAt = updatedAt
        self.archived = archived
        self.cwd = cwd
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.threadID = try container.decode(String.self, forKey: .threadID)
        if let hostID = try container.decodeIfPresent(UUID.self, forKey: .hostID) {
            self.hostID = hostID
        } else {
            self.hostID = try container.decode(UUID.self, forKey: .connectionID)
        }
        self.workspaceID = try container.decode(UUID.self, forKey: .workspaceID)
        self.preview = try container.decode(String.self, forKey: .preview)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        self.archived = try container.decode(Bool.self, forKey: .archived)
        self.cwd = try container.decode(String.self, forKey: .cwd)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.threadID, forKey: .threadID)
        try container.encode(self.hostID, forKey: .hostID)
        try container.encode(self.workspaceID, forKey: .workspaceID)
        try container.encode(self.preview, forKey: .preview)
        try container.encode(self.updatedAt, forKey: .updatedAt)
        try container.encode(self.archived, forKey: .archived)
        try container.encode(self.cwd, forKey: .cwd)
    }
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

protocol HostCredentialStore {
    func save(password: String, for hostID: UUID)
    func readPassword(for hostID: UUID) -> String?
    func deletePassword(for hostID: UUID)
}

struct KeychainHostCredentialStore: HostCredentialStore {
    func save(password: String, for hostID: UUID) {
        PasswordVault.save(password: password, for: hostID)
    }

    func readPassword(for hostID: UUID) -> String? {
        PasswordVault.readPassword(for: hostID)
    }

    func deletePassword(for hostID: UUID) {
        PasswordVault.deletePassword(for: hostID)
    }
}

final class InMemoryHostCredentialStore: HostCredentialStore {
    private var values: [UUID: String] = [:]

    func save(password: String, for hostID: UUID) {
        self.values[hostID] = password
    }

    func readPassword(for hostID: UUID) -> String? {
        self.values[hostID]
    }

    func deletePassword(for hostID: UUID) {
        self.values.removeValue(forKey: hostID)
    }
}

@MainActor
final class RemoteHostStore: ObservableObject {
    @Published private(set) var hosts: [RemoteHost] = []

    private let defaults: UserDefaults
    private let credentialStore: HostCredentialStore

    private let hostsKey = "codex.remote.hosts.v1"
    private let legacyRemoteHostsKey = "codex.remote.connections.v1"
    private let legacyProfilesKey = "ssh.connection.profiles.v1"

    init(
        defaults: UserDefaults = .standard,
        credentialStore: HostCredentialStore = KeychainHostCredentialStore()
    ) {
        self.defaults = defaults
        self.credentialStore = credentialStore
        self.loadHosts()
    }

    func upsert(hostID: UUID?, draft: RemoteHostDraft) {
        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHost = draft.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUser = draft.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAppServerHost = draft.appServerHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedAppServerHost = trimmedAppServerHost.isEmpty ? trimmedHost : trimmedAppServerHost
        let resolvedAppServerURL = RemoteHost.defaultAppServerURL(
            host: resolvedAppServerHost,
            port: draft.appServerPort
        )
        var updatedHosts = self.hosts

        if let hostID,
           let index = updatedHosts.firstIndex(where: { $0.id == hostID }) {
            var hostRecord = updatedHosts[index]
            hostRecord.name = trimmedName
            hostRecord.host = trimmedHost
            hostRecord.sshPort = draft.sshPort
            hostRecord.username = trimmedUser
            hostRecord.appServerURL = resolvedAppServerURL
            hostRecord.preferredTransport = draft.preferredTransport
            hostRecord.updatedAt = Date()
            updatedHosts[index] = hostRecord
            self.credentialStore.save(password: draft.password, for: hostID)
        } else {
            let hostRecord = RemoteHost(
                name: trimmedName,
                host: trimmedHost,
                sshPort: draft.sshPort,
                username: trimmedUser,
                appServerURL: resolvedAppServerURL,
                preferredTransport: draft.preferredTransport
            )
            updatedHosts.append(hostRecord)
            self.credentialStore.save(password: draft.password, for: hostRecord.id)
        }

        self.replaceHosts(updatedHosts, persist: true)
    }

    func delete(hostID: UUID) {
        self.replaceHosts(self.hosts.filter { $0.id != hostID }, persist: true)
        self.credentialStore.deletePassword(for: hostID)
    }

    func password(for hostID: UUID) -> String {
        self.credentialStore.readPassword(for: hostID) ?? ""
    }

    func updatePassword(_ password: String, for hostID: UUID) {
        self.credentialStore.save(password: password, for: hostID)
    }

    private func loadHosts() {
        if let data = self.defaults.data(forKey: self.hostsKey),
           let decoded = try? JSONDecoder().decode([RemoteHost].self, from: data) {
            self.replaceHosts(decoded, persist: false)
            return
        }

        if let data = self.defaults.data(forKey: self.legacyRemoteHostsKey),
           let decoded = try? JSONDecoder().decode([RemoteHost].self, from: data) {
            self.replaceHosts(decoded, persist: true)
            return
        }

        self.replaceHosts(self.migrateFromLegacyProfilesIfNeeded(), persist: true)
    }

    private func migrateFromLegacyProfilesIfNeeded() -> [RemoteHost] {
        guard let data = self.defaults.data(forKey: self.legacyProfilesKey),
              let legacyProfiles = try? JSONDecoder().decode([SSHHostProfile].self, from: data)
        else {
            return []
        }

        return legacyProfiles.map { profile in
            RemoteHost(
                id: profile.id,
                name: profile.name,
                host: profile.host,
                sshPort: profile.port,
                username: profile.username,
                appServerURL: RemoteHost.defaultAppServerURL(host: profile.host)
            )
        }
    }

    private func replaceHosts(_ hosts: [RemoteHost], persist: Bool) {
        self.hosts = hosts.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if persist {
            self.persistHosts()
        }
    }

    private func persistHosts() {
        guard let data = try? JSONEncoder().encode(self.hosts) else {
            self.defaults.removeObject(forKey: self.hostsKey)
            return
        }
        self.defaults.set(data, forKey: self.hostsKey)
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

    func workspaces(for hostID: UUID?) -> [ProjectWorkspace] {
        guard let hostID else { return [] }
        return self.workspaces.filter { $0.hostID == hostID }
    }

    func upsert(workspaceID: UUID?, hostID: UUID, draft: ProjectWorkspaceDraft) {
        let trimmedPath = draft.remotePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = draft.defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)

        if let workspaceID,
           let index = self.workspaces.firstIndex(where: { $0.id == workspaceID }) {
            self.workspaces[index].hostID = hostID
            self.workspaces[index].name = trimmedName
            self.workspaces[index].remotePath = trimmedPath
            self.workspaces[index].defaultModel = trimmedModel
            self.workspaces[index].defaultApprovalPolicy = draft.defaultApprovalPolicy
            self.workspaces[index].updatedAt = Date()
        } else {
            self.workspaces.append(
                ProjectWorkspace(
                    hostID: hostID,
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
        if lhs.hostID != rhs.hostID {
            return lhs.hostID.uuidString < rhs.hostID.uuidString
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

    func replaceThreads(for workspaceID: UUID, hostID: UUID, with summaries: [CodexThreadSummary]) {
        self.bookmarks.removeAll(where: { $0.workspaceID == workspaceID && $0.hostID == hostID })
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

struct TerminalLaunchContext: Equatable, Identifiable {
    let id: UUID = UUID()
    let hostID: UUID
    let projectPath: String?
    let threadID: String?
    let initialCommand: String
}

struct HostSessionContext: Identifiable, Codable, Equatable {
    var id: UUID { self.hostID }
    let hostID: UUID
    var selectedProjectID: UUID?
    var selectedThreadID: String?
    var lastActiveAt: Date
    var lastOpenedAt: Date
}

@MainActor
final class HostSessionStore: ObservableObject {
    @Published private(set) var sessions: [HostSessionContext] = []

    private let defaults: UserDefaults
    private let key = "codex.host.sessions.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.load()
    }

    func session(for hostID: UUID) -> HostSessionContext? {
        self.sessions.first(where: { $0.hostID == hostID })
    }

    func upsertSession(hostID: UUID) {
        let now = Date()
        if let index = self.sessions.firstIndex(where: { $0.hostID == hostID }) {
            self.sessions[index].lastActiveAt = now
        } else {
            self.sessions.append(
                HostSessionContext(
                    hostID: hostID,
                    selectedProjectID: nil,
                    selectedThreadID: nil,
                    lastActiveAt: now,
                    lastOpenedAt: now
                )
            )
        }
        self.persist()
    }

    func markOpened(hostID: UUID) {
        let now = Date()
        if let index = self.sessions.firstIndex(where: { $0.hostID == hostID }) {
            self.sessions[index].lastOpenedAt = now
            self.sessions[index].lastActiveAt = now
        } else {
            self.sessions.append(
                HostSessionContext(
                    hostID: hostID,
                    selectedProjectID: nil,
                    selectedThreadID: nil,
                    lastActiveAt: now,
                    lastOpenedAt: now
                )
            )
        }
        self.persist()
    }

    func selectProject(hostID: UUID, projectID: UUID?) {
        self.upsertSession(hostID: hostID)
        guard let index = self.sessions.firstIndex(where: { $0.hostID == hostID }) else { return }
        self.sessions[index].selectedProjectID = projectID
        if projectID == nil {
            self.sessions[index].selectedThreadID = nil
        }
        self.sessions[index].lastActiveAt = Date()
        self.persist()
    }

    func selectThread(hostID: UUID, threadID: String?) {
        self.upsertSession(hostID: hostID)
        guard let index = self.sessions.firstIndex(where: { $0.hostID == hostID }) else { return }
        self.sessions[index].selectedThreadID = threadID
        self.sessions[index].lastActiveAt = Date()
        self.persist()
    }

    func removeSession(hostID: UUID) {
        self.sessions.removeAll(where: { $0.hostID == hostID })
        self.persist()
    }

    func cleanupOrphans(validHostIDs: Set<UUID>) {
        self.sessions.removeAll(where: { validHostIDs.contains($0.hostID) == false })
        self.persist()
    }

    private func load() {
        guard let data = self.defaults.data(forKey: self.key),
              let decoded = try? JSONDecoder().decode([HostSessionContext].self, from: data)
        else {
            self.sessions = []
            return
        }
        self.sessions = decoded.sorted { $0.lastActiveAt > $1.lastActiveAt }
    }

    private func persist() {
        self.sessions.sort { $0.lastActiveAt > $1.lastActiveAt }
        guard let data = try? JSONEncoder().encode(self.sessions) else {
            self.defaults.removeObject(forKey: self.key)
            return
        }
        self.defaults.set(data, forKey: self.key)
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var selectedHostID: UUID?
    @Published var terminalLaunchContext: TerminalLaunchContext?

    let remoteHostStore: RemoteHostStore
    let projectStore: ProjectStore
    let threadBookmarkStore: ThreadBookmarkStore
    let hostSessionStore: HostSessionStore
    let appServerClient: AppServerClient

    init(
        remoteHostStore: RemoteHostStore = RemoteHostStore(),
        projectStore: ProjectStore = ProjectStore(),
        threadBookmarkStore: ThreadBookmarkStore = ThreadBookmarkStore(),
        hostSessionStore: HostSessionStore = HostSessionStore(),
        appServerClient: AppServerClient = AppServerClient()
    ) {
        self.remoteHostStore = remoteHostStore
        self.projectStore = projectStore
        self.threadBookmarkStore = threadBookmarkStore
        self.hostSessionStore = hostSessionStore
        self.appServerClient = appServerClient

        self.selectedHostID = remoteHostStore.hosts.first?.id
        self.cleanupSessionOrphans()
    }

    var selectedHost: RemoteHost? {
        guard let selectedHostID else { return nil }
        return self.remoteHostStore.hosts.first(where: { $0.id == selectedHostID })
    }

    func selectHost(_ hostID: UUID?) {
        self.selectedHostID = hostID
        if let hostID {
            self.hostSessionStore.upsertSession(hostID: hostID)
        }
    }

    func removeHost(hostID: UUID) {
        self.remoteHostStore.delete(hostID: hostID)
        self.hostSessionStore.removeSession(hostID: hostID)
        self.projectStore.workspaces
            .filter { $0.hostID == hostID }
            .forEach { workspace in
                self.threadBookmarkStore
                    .threads(for: workspace.id)
                    .forEach { summary in
                        self.threadBookmarkStore.remove(threadID: summary.threadID, workspaceID: workspace.id)
                    }
                self.projectStore.delete(workspaceID: workspace.id)
            }
        if self.selectedHostID == hostID {
            self.selectedHostID = self.remoteHostStore.hosts.first?.id
        }
        self.cleanupSessionOrphans()
    }

    func cleanupSessionOrphans() {
        let validHostIDs = Set(self.remoteHostStore.hosts.map(\.id))
        self.hostSessionStore.cleanupOrphans(validHostIDs: validHostIDs)
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
    let jsonrpc: String?
    let id: JSONValue?
    let method: String?
    let params: JSONValue?
    let result: JSONValue?
    let error: JSONRPCErrorPayload?

    init(
        jsonrpc: String? = nil,
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
    case invalidEndpointHost(String)
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
        case .invalidEndpointHost(let host):
            return "Invalid app-server host (\(host)). Use a reachable host or Tailscale IP, not 0.0.0.0/localhost."
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
    private var lastHost: RemoteHost?
    private var hasReceivedMessageOnCurrentConnection = false

    private let requestTimeoutSeconds: TimeInterval = 30

    init(session: URLSession = .shared) {
        self.session = session
    }

    func connect(to host: RemoteHost) async throws {
        try await self.openConnection(to: host, resetReconnectAttempts: true)
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
        if let preferred = self.preferredUserFacingMessage(for: error) {
            return preferred
        }

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

    private func openConnection(to host: RemoteHost, resetReconnectAttempts: Bool) async throws {
        let url = try Self.resolveAppServerURL(raw: host.appServerURL)

        self.reconnectTask?.cancel()
        self.teardownConnection(closeCode: .normalClosure)

        if resetReconnectAttempts {
            self.reconnectAttempts = 0
        }

        self.state = .connecting
        self.lastErrorMessage = ""
        self.autoReconnectEnabled = true
        self.lastHost = host
        self.connectedEndpoint = url.absoluteString
        self.diagnostics = AppServerDiagnostics(
            minimumRequiredVersion: Self.minimumSupportedCLIVersion
        )

        let task = self.session.webSocketTask(with: url)
        self.webSocketTask = task
        self.hasReceivedMessageOnCurrentConnection = false
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
            try await self.sendEnvelope(
                JSONRPCEnvelope(
                    method: "initialized"
                )
            )
            if let cliVersion = self.nonEmptyOrNil(self.diagnostics.cliVersion),
               !Self.isVersion(cliVersion, atLeast: Self.minimumSupportedCLIVersion) {
                throw AppServerClientError.incompatibleVersion(
                    current: cliVersion,
                    minimum: Self.minimumSupportedCLIVersion
                )
            }
            self.state = .connected
            self.diagnostics.lastCheckedAt = Date()
            self.appendEvent("Connected: \(host.name) @ \(url.absoluteString)")
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
        self.hasReceivedMessageOnCurrentConnection = true

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

    func applyNotificationForTesting(method: String, params: JSONValue?) {
        self.handleNotification(method: method, params: params)
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
        let shouldAttemptReconnect = self.shouldAttemptReconnect(after: error)

        self.lastErrorMessage = self.userFacingMessage(for: error)
        self.state = .disconnected
        self.connectedEndpoint = ""
        self.activeTurnIDByThread.removeAll()
        self.teardownConnection(closeCode: .abnormalClosure)

        guard shouldAttemptReconnect,
              self.autoReconnectEnabled,
              let host = self.lastHost
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
                try await self.openConnection(to: host, resetReconnectAttempts: false)
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
        self.hasReceivedMessageOnCurrentConnection = false
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

    static func resolveAppServerURL(raw: String) throws -> URL {
        let normalizedRaw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedRaw.isEmpty else {
            throw AppServerClientError.invalidURL
        }

        guard let components = URLComponents(string: normalizedRaw),
              let scheme = components.scheme?.lowercased(),
              scheme == "ws" || scheme == "wss"
        else {
            throw AppServerClientError.invalidURL
        }

        guard let endpointHost = components.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !endpointHost.isEmpty
        else {
            throw AppServerClientError.invalidURL
        }

        guard Self.isUnroutableEndpointHost(endpointHost) == false else {
            throw AppServerClientError.invalidEndpointHost(endpointHost)
        }

        guard let resolvedURL = components.url else {
            throw AppServerClientError.invalidURL
        }
        return resolvedURL
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

    private static func isUnroutableEndpointHost(_ host: String) -> Bool {
        switch host.lowercased() {
        case "0.0.0.0", "::", "::1", "localhost", "127.0.0.1":
            return true
        default:
            return false
        }
    }

    private static func errorCategory(for error: Error) -> AppServerErrorCategory {
        if let appServerError = error as? AppServerClientError {
            switch appServerError {
            case .incompatibleVersion:
                return .compatibility
            case .invalidURL, .invalidEndpointHost, .notConnected, .timeout:
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

    private func preferredUserFacingMessage(for error: Error) -> String? {
        guard let urlError = error as? URLError,
              urlError.code == .networkConnectionLost,
              !self.hasReceivedMessageOnCurrentConnection
        else {
            return nil
        }

        return "[Connection] WebSocket handshake failed before app-server initialization. codex app-server may reject iOS WebSocket extension negotiation (Sec-WebSocket-Extensions). Use Terminal tab, or connect through a WebSocket proxy."
    }

    private func shouldAttemptReconnect(after error: Error) -> Bool {
        guard let urlError = error as? URLError else {
            return true
        }

        if urlError.code == .networkConnectionLost,
           !self.hasReceivedMessageOnCurrentConnection {
            return false
        }

        return true
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
        HostsView()
        .sheet(item: self.$appState.terminalLaunchContext) { _ in
            TerminalView()
        }
    }
}

struct HostsView: View {
    @EnvironmentObject private var appState: AppState

    @State private var editorContext: HostEditorContext?

    var body: some View {
        NavigationStack {
            Group {
                if self.appState.remoteHostStore.hosts.isEmpty {
                    ContentUnavailableView(
                        "No Hosts",
                        systemImage: "network",
                        description: Text("Tap + to add your first host.")
                    )
                } else {
                    List {
                        ForEach(self.appState.remoteHostStore.hosts) { host in
                            NavigationLink {
                                SessionWorkbenchView(host: host)
                            } label: {
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
                                            .textSelection(.enabled)
                                    }

                                    Spacer(minLength: 8)

                                    if self.appState.selectedHostID == host.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    }
                                }
                            }
                            .simultaneousGesture(
                                TapGesture().onEnded {
                                    self.appState.selectHost(host.id)
                                }
                            )
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Delete", role: .destructive) {
                                    self.appState.removeHost(hostID: host.id)
                                }

                                Button("Edit") {
                                    self.editorContext = HostEditorContext(
                                        host: host,
                                        initialPassword: self.appState.remoteHostStore.password(for: host.id)
                                    )
                                }
                                .tint(.orange)

                                Button("Terminal") {
                                    self.appState.terminalLaunchContext = TerminalLaunchContext(
                                        hostID: host.id,
                                        projectPath: nil,
                                        threadID: nil,
                                        initialCommand: "codex"
                                    )
                                }
                                .tint(.blue)
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
                    .codexActionButtonStyle()
                }
            }
        }
        .sheet(item: self.$editorContext) { context in
            RemoteHostEditorView(
                host: context.host,
                initialPassword: context.initialPassword
            ) { draft in
                self.appState.remoteHostStore.upsert(hostID: context.host?.id, draft: draft)
                self.appState.cleanupSessionOrphans()
            }
        }
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
    @State private var preferredTransport: TransportKind

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
        _preferredTransport = State(initialValue: initialDraft.preferredTransport)
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
            preferredTransport: self.preferredTransport,
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

                    Picker("Transport", selection: self.$preferredTransport) {
                        ForEach(TransportKind.allCases) { transport in
                            Text(transport.displayName).tag(transport)
                        }
                    }
                }

                Section("SSH") {
                    SecureField("Password (optional)", text: self.$password)
                }
            }
            .navigationTitle(self.host == nil ? "New Host" : "Edit Host")
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
                    let command = "printf '\(startMarker)\\n'; cd '\(escapedPath)' 2>/dev/null || cd /; pwd; LC_ALL=C ls -1Ap; printf '\(endMarker)\\n'"
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
            guard raw.hasSuffix("/") else { return nil }
            let name = String(raw.dropLast())
            guard name != "." && name != ".." && !name.isEmpty else { return nil }
            let fullPath = currentPath == "/" ? "/\(name)" : "\(currentPath)/\(name)"
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

    private let service = RemotePathBrowserService()

    var body: some View {
        NavigationStack {
            List {
                Section("Current") {
                    Text(self.currentPath.isEmpty ? self.initialPath : self.currentPath)
                        .font(.footnote)
                        .textSelection(.enabled)
                }

                if let parentPath = self.parentPath(of: self.currentPath) {
                    Section {
                        Button("..") {
                            self.load(path: parentPath)
                        }
                    }
                }

                Section("Directories") {
                    if self.entries.isEmpty {
                        Text(self.isLoading ? "Loading..." : "No subdirectories")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(self.entries) { entry in
                            Button(entry.name) {
                                self.load(path: entry.path)
                            }
                        }
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        self.dismiss()
                    }
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
        self.errorMessage = ""
        self.isLoading = true

        Task {
            defer {
                self.isLoading = false
            }

            do {
                let (resolvedPath, directories) = try await self.service.listDirectories(
                    host: self.host,
                    password: self.hostPassword,
                    path: path
                )
                self.currentPath = resolvedPath
                self.entries = directories
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
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
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let host: RemoteHost

    @State private var selectedWorkspaceID: UUID?
    @State private var selectedThreadID: String?
    @State private var prompt = ""
    @State private var localErrorMessage = ""
    @State private var localStatusMessage = ""
    @State private var isRefreshingThreads = false
    @State private var isRunningSSHAction = false
    @State private var showArchived = false
    @State private var isPresentingDiagnostics = false
    @State private var isPresentingProjectEditor = false
    @State private var editingWorkspace: ProjectWorkspace?
    @State private var activePendingRequest: AppServerPendingRequest?
    @State private var sshTranscriptByThread: [String: String] = [:]
    @State private var isMenuOpen = false
    @State private var expandedWorkspaceIDs: Set<UUID> = []
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

    private func threads(for workspaceID: UUID) -> [CodexThreadSummary] {
        self.appState.threadBookmarkStore
            .threads(for: workspaceID)
            .filter { $0.archived == self.showArchived }
    }

    private var selectedThreadTranscript: String {
        guard let selectedThreadID else { return "" }
        if self.isSSHTransport {
            return self.sshTranscriptByThread[selectedThreadID] ?? ""
        }
        return self.appState.appServerClient.transcriptByThread[selectedThreadID] ?? ""
    }

    private var selectedWorkspaceTitle: String {
        self.selectedWorkspace?.displayName ?? "プロジェクト"
    }

    private var parsedChatMessages: [SessionChatMessage] {
        Self.parseChatMessages(from: self.selectedThreadTranscript)
    }

    private var isPromptEmpty: Bool {
        self.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var menuWidth: CGFloat {
        304
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
                Color.black.opacity(0.18)
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

            self.sideMenu
                .zIndex(2)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            self.chatHeader
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
                self.selectWorkspace(firstWorkspace)
            }
            if let selectedWorkspaceID {
                self.expandedWorkspaceIDs.insert(selectedWorkspaceID)
            }
            if self.isSSHTransport {
                self.appState.appServerClient.disconnect()
            }
            if self.selectedWorkspace != nil {
                self.refreshThreads()
            }
        }
        .onChange(of: self.showArchived) {
            self.refreshThreads()
        }
        .onChange(of: self.selectedWorkspaceID) {
            if let selectedWorkspaceID {
                self.expandedWorkspaceIDs.insert(selectedWorkspaceID)
            }
        }
        .sheet(isPresented: self.$isPresentingProjectEditor) {
            ProjectEditorView(
                workspace: self.editingWorkspace,
                host: self.host,
                hostPassword: self.appState.remoteHostStore.password(for: self.host.id)
            ) { draft in
                self.appState.projectStore.upsert(
                    workspaceID: self.editingWorkspace?.id,
                    hostID: self.host.id,
                    draft: draft
                )
                self.restoreSelectionFromSession()
            }
        }
        .sheet(isPresented: self.$isPresentingDiagnostics) {
            HostDiagnosticsView()
                .environmentObject(self.appState)
        }
        .sheet(item: self.$activePendingRequest) { request in
            PendingRequestSheet(request: request)
                .environmentObject(self.appState)
        }
    }

    private var chatBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.88, green: 0.94, blue: 1.00),
                    Color(red: 0.95, green: 0.98, blue: 1.00),
                    Color(red: 0.90, green: 0.96, blue: 0.96),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.accentColor.opacity(0.24))
                .frame(width: 320, height: 320)
                .blur(radius: 50)
                .offset(x: -170, y: -250)

            Circle()
                .fill(Color.cyan.opacity(0.18))
                .frame(width: 300, height: 300)
                .blur(radius: 56)
                .offset(x: 180, y: 230)
        }
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
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .background {
                        self.glassCircleBackground(size: 38)
                    }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.primary)

            VStack(spacing: 1) {
                Text(self.selectedWorkspaceTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text(self.host.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)

            Button {
                self.isPromptFieldFocused = false
                self.createNewThread()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 38, height: 38)
                    .background {
                        self.glassCircleBackground(size: 38, tint: Color.accentColor.opacity(0.28))
                    }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            self.glassCardBackground(cornerRadius: 26, tint: Color.white.opacity(0.24))
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var chatTimeline: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    if !self.localErrorMessage.isEmpty {
                        Label(self.localErrorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background {
                                self.glassCardBackground(cornerRadius: 14, tint: Color.red.opacity(0.18))
                            }
                    }

                    if !self.localStatusMessage.isEmpty {
                        Label(self.localStatusMessage, systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background {
                                self.glassCardBackground(cornerRadius: 14)
                            }
                    }

                    if !self.isSSHTransport,
                       !self.appState.appServerClient.pendingRequests.isEmpty {
                        Button {
                            self.activePendingRequest = self.appState.appServerClient.pendingRequests.first
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "clock.badge.exclamationmark")
                                Text("承認待ち \(self.appState.appServerClient.pendingRequests.count) 件")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background {
                                self.glassCardBackground(cornerRadius: 14, tint: Color.orange.opacity(0.18))
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    if self.selectedWorkspace == nil {
                        VStack(spacing: 10) {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 28, weight: .light))
                            Text("プロジェクトを作成または選択してください。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 240)
                        .background {
                            self.glassCardBackground(cornerRadius: 22)
                        }
                    } else if self.selectedThreadID == nil {
                        VStack(spacing: 10) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 26, weight: .light))
                            Text("スレッドを選択するか、＋で新規スレッドを作成してください。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 240)
                        .background {
                            self.glassCardBackground(cornerRadius: 22)
                        }
                    } else if self.parsedChatMessages.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "text.bubble")
                                .font(.system(size: 26, weight: .light))
                            Text("まだメッセージはありません。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 220)
                        .background {
                            self.glassCardBackground(cornerRadius: 22)
                        }
                    } else {
                        ForEach(self.parsedChatMessages) { message in
                            HStack(alignment: .bottom, spacing: 0) {
                                if message.role == .user {
                                    Spacer(minLength: 48)
                                }

                                Text(message.text)
                                    .font(.subheadline)
                                    .foregroundStyle(message.role == .user ? Color.white : Color.primary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 11)
                                    .textSelection(.enabled)
                                    .background {
                                        self.chatBubbleBackground(for: message.role)
                                    }
                                    .frame(maxWidth: 300, alignment: message.role == .user ? .trailing : .leading)

                                if message.role == .assistant {
                                    Spacer(minLength: 48)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
                        }
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("chat-bottom")
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 14)
            }
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
        }
    }

    private var chatComposer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("メッセージを入力...", text: self.$prompt, axis: .vertical)
                .lineLimit(1...4)
                .textInputAutocapitalization(.sentences)
                .focused(self.$isPromptFieldFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Button {
                self.isPromptFieldFocused = false
                self.sendPrompt(forceNewThread: false)
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 40, height: 40)
                    .background {
                        self.glassCircleBackground(size: 40, tint: Color.accentColor.opacity(0.52))
                    }
            }
            .buttonStyle(.plain)
            .disabled(
                self.isPromptEmpty
                || self.isRunningSSHAction
                || self.selectedWorkspace == nil
            )
            .opacity(
                self.isPromptEmpty || self.selectedWorkspace == nil
                ? 0.45
                : 1
            )
        }
        .padding(8)
        .background {
            self.glassCardBackground(cornerRadius: 24, tint: Color.white.opacity(0.24))
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    private var sideMenu: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(self.host.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(self.host.host)
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
                VStack(spacing: 8) {
                    Toggle(isOn: self.$showArchived) {
                        Label("アーカイブを表示", systemImage: "archivebox")
                            .font(.subheadline.weight(.medium))
                    }
                    .toggleStyle(.switch)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background {
                        self.glassCardBackground(cornerRadius: 14)
                    }

                    if self.workspaces.isEmpty {
                        Text("プロジェクトがありません。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                            .background {
                                self.glassCardBackground(cornerRadius: 14)
                            }
                    } else {
                        ForEach(self.workspaces) { workspace in
                            let workspaceThreads = self.threads(for: workspace.id)
                            let isExpanded = self.expandedWorkspaceIDs.contains(workspace.id)
                            let isCurrentWorkspace = self.selectedWorkspaceID == workspace.id

                            VStack(spacing: 6) {
                                Button {
                                    self.toggleWorkspace(workspace)
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                        Text(workspace.displayName)
                                            .font(.subheadline.weight(.semibold))
                                            .lineLimit(1)
                                        Spacer(minLength: 8)
                                        Text("\(workspaceThreads.count)")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background {
                                        self.glassCardBackground(
                                            cornerRadius: 14,
                                            tint: isCurrentWorkspace
                                            ? Color.accentColor.opacity(0.20)
                                            : Color.white.opacity(0.18)
                                        )
                                    }
                                }
                                .buttonStyle(.plain)

                                if isExpanded {
                                    if workspaceThreads.isEmpty {
                                        Text("スレッドなし")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 9)
                                    } else {
                                        ForEach(workspaceThreads) { summary in
                                            Button {
                                                self.selectThread(summary, workspaceID: workspace.id)
                                            } label: {
                                                HStack(spacing: 8) {
                                                    Image(systemName: "bubble.left")
                                                        .font(.system(size: 12, weight: .medium))
                                                    Text(summary.preview.isEmpty ? "新規スレッド" : summary.preview)
                                                        .font(.subheadline)
                                                        .lineLimit(1)
                                                    Spacer(minLength: 8)
                                                }
                                                .foregroundStyle(
                                                    self.selectedThreadID == summary.threadID
                                                    ? Color.accentColor
                                                    : Color.primary
                                                )
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 10)
                                                .background {
                                                    self.glassCardBackground(
                                                        cornerRadius: 12,
                                                        tint: self.selectedThreadID == summary.threadID
                                                        ? Color.accentColor.opacity(0.22)
                                                        : Color.white.opacity(0.12)
                                                    )
                                                }
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Button {
                        self.editingWorkspace = nil
                        self.isPresentingProjectEditor = true
                        self.isMenuOpen = false
                    } label: {
                        Label("プロジェクト追加", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background {
                                self.glassCardBackground(cornerRadius: 14, tint: Color.accentColor.opacity(0.18))
                            }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 2)
            }

            VStack(spacing: 8) {
                Button {
                    self.isMenuOpen = false
                    self.refreshThreads()
                } label: {
                    Label("スレッド更新", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background {
                            self.glassCardBackground(cornerRadius: 14)
                        }
                }
                .buttonStyle(.plain)
                .disabled(self.selectedWorkspace == nil || self.isRefreshingThreads || self.isRunningSSHAction)
                .opacity(self.selectedWorkspace == nil ? 0.5 : 1)

                HStack(spacing: 8) {
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

                    if !self.isSSHTransport {
                        Button {
                            self.isMenuOpen = false
                            self.isPresentingDiagnostics = true
                        } label: {
                            Label("Diagnostics", systemImage: "waveform.path.ecg")
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background {
                                    self.glassCardBackground(cornerRadius: 12)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button {
                    self.isMenuOpen = false
                    self.dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                        Text("ホスト一覧に戻る")
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
        .padding(.vertical, 12)
        .frame(width: self.menuWidth)
        .frame(maxHeight: .infinity)
        .background {
            self.glassCardBackground(cornerRadius: 30, tint: Color.white.opacity(0.24))
        }
        .padding(.leading, 8)
        .padding(.vertical, 8)
        .offset(x: self.isMenuOpen ? 0 : -(self.menuWidth + 20))
        .shadow(color: .black.opacity(self.isMenuOpen ? 0.14 : 0), radius: 16, x: 0, y: 10)
    }

    @ViewBuilder
    private func glassCardBackground(cornerRadius: CGFloat, tint: Color = Color.white.opacity(0.18)) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            shape
                .fill(tint)
                .glassEffect(.regular, in: shape)
        } else {
            shape
                .fill(.ultraThinMaterial)
                .overlay(
                    shape.strokeBorder(Color.white.opacity(0.30), lineWidth: 0.8)
                )
        }
    }

    @ViewBuilder
    private func glassCircleBackground(size: CGFloat, tint: Color = Color.white.opacity(0.20)) -> some View {
        let circle = Circle()
        if #available(iOS 26.0, *) {
            circle
                .fill(tint)
                .glassEffect(.regular, in: circle)
        } else {
            circle
                .fill(.ultraThinMaterial)
                .overlay(
                    circle.strokeBorder(Color.white.opacity(0.30), lineWidth: 0.8)
                )
        }
    }

    @ViewBuilder
    private func chatBubbleBackground(for role: SessionChatRole) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

        if role == .user {
            if #available(iOS 26.0, *) {
                shape
                    .fill(Color.accentColor.opacity(0.52))
                    .glassEffect(.regular, in: shape)
            } else {
                shape
                    .fill(Color.accentColor)
                    .overlay(
                        shape.strokeBorder(Color.white.opacity(0.28), lineWidth: 0.8)
                    )
            }
        } else {
            if #available(iOS 26.0, *) {
                shape
                    .fill(Color.white.opacity(0.22))
                    .glassEffect(.regular, in: shape)
            } else {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(
                        shape.strokeBorder(Color.white.opacity(0.30), lineWidth: 0.8)
                    )
            }
        }
    }
    private func scrollToBottom(proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo("chat-bottom", anchor: .bottom)
            }
        }
    }

    private func toggleWorkspace(_ workspace: ProjectWorkspace) {
        self.selectWorkspace(workspace)
        if self.expandedWorkspaceIDs.contains(workspace.id) {
            self.expandedWorkspaceIDs.remove(workspace.id)
        } else {
            self.expandedWorkspaceIDs.insert(workspace.id)
        }
    }

    private func selectWorkspace(_ workspace: ProjectWorkspace) {
        self.selectedWorkspaceID = workspace.id
        let workspaceThreads = self.threads(for: workspace.id)
        if let selectedThreadID,
           workspaceThreads.contains(where: { $0.threadID == selectedThreadID }) {
            // Keep current thread.
        } else {
            self.selectedThreadID = workspaceThreads.first?.threadID
            self.appState.hostSessionStore.selectThread(hostID: self.host.id, threadID: self.selectedThreadID)
            if let selectedThreadID {
                self.loadThread(selectedThreadID)
            }
        }
        self.appState.hostSessionStore.selectProject(hostID: self.host.id, projectID: workspace.id)
    }

    private func selectThread(_ summary: CodexThreadSummary, workspaceID: UUID) {
        self.selectedWorkspaceID = workspaceID
        self.selectedThreadID = summary.threadID
        self.appState.hostSessionStore.selectProject(hostID: self.host.id, projectID: workspaceID)
        self.appState.hostSessionStore.selectThread(hostID: self.host.id, threadID: summary.threadID)
        self.loadThread(summary.threadID)
        self.isMenuOpen = false
    }

    private func createNewThread() {
        self.localErrorMessage = ""
        self.localStatusMessage = ""

        guard let selectedWorkspace else {
            self.localErrorMessage = "先にプロジェクトを選択してください。"
            return
        }

        if self.isSSHTransport {
            self.selectedThreadID = nil
            self.appState.hostSessionStore.selectThread(hostID: self.host.id, threadID: nil)
            self.localStatusMessage = "次の送信で新規スレッドを開始します。"
            return
        }

        Task {
            do {
                if self.appState.appServerClient.state != .connected {
                    try await self.appState.appServerClient.connect(to: self.host)
                }

                let threadID = try await self.appState.appServerClient.threadStart(
                    cwd: selectedWorkspace.remotePath,
                    approvalPolicy: selectedWorkspace.defaultApprovalPolicy,
                    model: selectedWorkspace.defaultModel
                )

                self.selectedThreadID = threadID
                self.appState.hostSessionStore.selectThread(hostID: self.host.id, threadID: threadID)
                self.appState.threadBookmarkStore.upsert(
                    summary: CodexThreadSummary(
                        threadID: threadID,
                        hostID: self.host.id,
                        workspaceID: selectedWorkspace.id,
                        preview: "新規スレッド",
                        updatedAt: Date(),
                        archived: false,
                        cwd: selectedWorkspace.remotePath
                    )
                )
                self.localStatusMessage = "新規スレッドを作成しました。"
            } catch {
                self.localErrorMessage = self.appState.appServerClient.userFacingMessage(for: error)
            }
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

            if line.hasPrefix("> ") {
                flushCurrent()
                currentRole = .user
                buffer = [String(line.dropFirst(2))]
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
                if currentRole != .assistant {
                    flushCurrent()
                    currentRole = .assistant
                    buffer = []
                }
                buffer.append(line)
                continue
            }

            if line.isEmpty {
                if !buffer.isEmpty {
                    buffer.append("")
                }
                continue
            }

            if currentRole == nil {
                currentRole = .assistant
            }
            buffer.append(line)
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

        if let selectedThreadID = session?.selectedThreadID {
            self.selectedThreadID = selectedThreadID
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
                    .filter { $0.archived == self.showArchived }
                if let selectedThreadID,
                   localThreads.contains(where: { $0.threadID == selectedThreadID }) {
                    // Keep current selection.
                } else {
                    self.selectedThreadID = localThreads.first?.threadID
                    self.appState.hostSessionStore.selectThread(hostID: self.host.id, threadID: self.selectedThreadID)
                }
                self.localStatusMessage = "SSH mode: showing locally saved threads."
                return
            }

            do {
                if self.appState.appServerClient.state != .connected {
                    try await self.appState.appServerClient.connect(to: self.host)
                }

                let fetched = try await self.appState.appServerClient.threadList(archived: self.showArchived, limit: 100)
                let scoped = fetched.filter { $0.cwd == selectedWorkspace.remotePath }

                let summaries = scoped.map { thread in
                    CodexThreadSummary(
                        threadID: thread.id,
                        hostID: self.host.id,
                        workspaceID: selectedWorkspace.id,
                        preview: thread.preview,
                        updatedAt: thread.updatedAt,
                        archived: thread.archived,
                        cwd: thread.cwd
                    )
                }

                self.appState.threadBookmarkStore.replaceThreads(
                    for: selectedWorkspace.id,
                    hostID: self.host.id,
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
                        model: selectedWorkspace.defaultModel
                    )
                }

                guard let threadID else {
                    self.localErrorMessage = "Failed to resolve thread."
                    return
                }

                self.selectedThreadID = threadID
                self.appState.hostSessionStore.selectThread(hostID: self.host.id, threadID: threadID)

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
                        hostID: self.host.id,
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
                    model: selectedWorkspace.defaultModel
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
            existing += "\n\n"
        }
        existing += "> \(prompt)\n\(response)"
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
                _ = try await self.appState.appServerClient.threadRead(threadID: threadID)
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
