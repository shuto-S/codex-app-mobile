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

enum HostAuthMode: String, Codable, CaseIterable, Identifiable {
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

struct RemoteHost: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var host: String
    var sshPort: Int
    var username: String
    var appServerURL: String
    var preferredTransport: TransportKind
    var authMode: HostAuthMode
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
        authMode: HostAuthMode = .remotePCManaged,
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

struct RemoteHostDraft {
    var name: String
    var host: String
    var sshPort: Int
    var username: String
    var appServerURL: String
    var preferredTransport: TransportKind
    var authMode: HostAuthMode
    var password: String

    static let empty = RemoteHostDraft(
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
        authMode: HostAuthMode,
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

    init(host: RemoteHost, password: String) {
        self.name = host.name
        self.host = host.host
        self.sshPort = host.sshPort
        self.username = host.username
        self.appServerURL = host.appServerURL
        self.preferredTransport = host.preferredTransport
        self.authMode = host.authMode
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
        let trimmedURL = draft.appServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        var updatedHosts = self.hosts

        if let hostID,
           let index = updatedHosts.firstIndex(where: { $0.id == hostID }) {
            var hostRecord = updatedHosts[index]
            hostRecord.name = trimmedName
            hostRecord.host = trimmedHost
            hostRecord.sshPort = draft.sshPort
            hostRecord.username = trimmedUser
            hostRecord.appServerURL = trimmedURL
            hostRecord.preferredTransport = draft.preferredTransport
            hostRecord.authMode = draft.authMode
            hostRecord.updatedAt = Date()
            updatedHosts[index] = hostRecord
            self.credentialStore.save(password: draft.password, for: hostID)
        } else {
            let hostRecord = RemoteHost(
                name: trimmedName,
                host: trimmedHost,
                sshPort: draft.sshPort,
                username: trimmedUser,
                appServerURL: trimmedURL,
                preferredTransport: draft.preferredTransport,
                authMode: draft.authMode
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

enum AppRootTab: Hashable {
    case hosts
    case sessions
    case terminal
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
    @Published var selectedTab: AppRootTab = .hosts
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

    func openHostSession(_ hostID: UUID) {
        self.selectHost(hostID)
        self.hostSessionStore.markOpened(hostID: hostID)
        self.selectedTab = .sessions
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
        self.lastErrorMessage = self.userFacingMessage(for: error)
        self.state = .disconnected
        self.connectedEndpoint = ""
        self.activeTurnIDByThread.removeAll()
        self.teardownConnection(closeCode: .abnormalClosure)

        guard self.autoReconnectEnabled,
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
            HostsTabView()
                .tabItem {
                    Label("Hosts", systemImage: "network")
                }
                .tag(AppRootTab.hosts)

            SessionsTabView()
                .tabItem {
                    Label("Sessions", systemImage: "clock.arrow.circlepath")
                }
                .tag(AppRootTab.sessions)

            TerminalTabView()
                .tabItem {
                    Label("Terminal", systemImage: "terminal")
                }
                .tag(AppRootTab.terminal)
        }
    }
}

struct HostsTabView: View {
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
                            Button {
                                self.appState.openHostSession(host.id)
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
                            .buttonStyle(.plain)
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
    @State private var appServerURL: String
    @State private var password: String
    @State private var preferredTransport: TransportKind
    @State private var authMode: HostAuthMode

    init(host: RemoteHost?, initialPassword: String, onSave: @escaping (RemoteHostDraft) -> Void) {
        self.host = host
        self.initialPassword = initialPassword
        self.onSave = onSave

        _displayName = State(initialValue: host?.name ?? "")
        _hostAddress = State(initialValue: host?.host ?? "")
        _sshPortText = State(initialValue: String(host?.sshPort ?? 22))
        _username = State(initialValue: host?.username ?? "")
        _appServerURL = State(initialValue: host?.appServerURL ?? "")
        _password = State(initialValue: initialPassword)
        _preferredTransport = State(initialValue: host?.preferredTransport ?? .appServerWS)
        _authMode = State(initialValue: host?.authMode ?? .remotePCManaged)
    }

    private var parsedPort: Int {
        Int(self.sshPortText) ?? 22
    }

    private var draft: RemoteHostDraft {
        RemoteHostDraft(
            name: self.displayName,
            host: self.hostAddress,
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
                        ForEach(HostAuthMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                }

                Section("SSH") {
                    SecureField("Password (optional)", text: self.$password)
                }

                if self.host == nil {
                    Section {
                        Button("Generate app-server URL from host") {
                            let normalized = self.hostAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !normalized.isEmpty else { return }
                            self.appServerURL = RemoteHost.defaultAppServerURL(host: normalized)
                        }
                    }
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

struct SessionsTabView: View {
    @EnvironmentObject private var appState: AppState

    private var sessionRows: [HostSessionContext] {
        self.appState.hostSessionStore.sessions.filter { context in
            self.appState.remoteHostStore.hosts.contains(where: { $0.id == context.hostID })
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if self.sessionRows.isEmpty {
                    ContentUnavailableView(
                        "No Sessions",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Select a host from Hosts tab to create a resumable session.")
                    )
                } else {
                    List {
                        ForEach(self.sessionRows) { context in
                            if let host = self.appState.remoteHostStore.hosts.first(where: { $0.id == context.hostID }) {
                                NavigationLink {
                                    SessionWorkbenchView(host: host)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(host.name)
                                            .font(.headline)
                                        Text("\(host.username)@\(host.host):\(host.sshPort)")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        Text("Last active: \(context.lastActiveAt.formatted(date: .abbreviated, time: .shortened))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button("Remove", role: .destructive) {
                                        self.appState.hostSessionStore.removeSession(hostID: context.hostID)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Sessions")
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

struct SessionWorkbenchView: View {
    @EnvironmentObject private var appState: AppState

    let host: RemoteHost

    @State private var selectedWorkspaceID: UUID?
    @State private var selectedThreadID: String?
    @State private var prompt = ""
    @State private var localErrorMessage = ""
    @State private var isRefreshingThreads = false
    @State private var showArchived = false
    @State private var isPresentingDiagnostics = false
    @State private var isPresentingProjectEditor = false
    @State private var editingWorkspace: ProjectWorkspace?
    @State private var activePendingRequest: AppServerPendingRequest?

    private var selectedWorkspace: ProjectWorkspace? {
        guard let selectedWorkspaceID else { return nil }
        return self.workspaces.first(where: { $0.id == selectedWorkspaceID })
    }

    private var workspaces: [ProjectWorkspace] {
        self.appState.projectStore.workspaces(for: self.host.id)
    }

    private var threads: [CodexThreadSummary] {
        self.appState.threadBookmarkStore.threads(for: self.selectedWorkspaceID)
    }

    private var selectedThreadTranscript: String {
        guard let selectedThreadID else { return "" }
        return self.appState.appServerClient.transcriptByThread[selectedThreadID] ?? ""
    }

    var body: some View {
        List {
            Section("Status") {
                Text("Host: \(self.host.name)")
                Text("\(self.host.username)@\(self.host.host):\(self.host.sshPort)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text("State: \(self.appState.appServerClient.state.rawValue)")

                if !self.appState.appServerClient.connectedEndpoint.isEmpty {
                    Text("Endpoint: \(self.appState.appServerClient.connectedEndpoint)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
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
                        self.connectHost()
                    }
                    .disabled(self.appState.appServerClient.state == .connected)
                    .codexActionButtonStyle()

                    Button("Disconnect") {
                        self.appState.appServerClient.disconnect()
                    }
                    .disabled(self.appState.appServerClient.state == .disconnected)
                    .codexActionButtonStyle()

                    Button("Refresh") {
                        self.refreshThreads()
                    }
                    .disabled(self.selectedWorkspace == nil || self.isRefreshingThreads)
                    .codexActionButtonStyle()
                }

                Toggle("Show Archived", isOn: self.$showArchived)

                HStack {
                    Button("Open in Terminal") {
                        self.openInTerminal()
                    }
                    .codexActionButtonStyle()

                    Button("Diagnostics") {
                        self.isPresentingDiagnostics = true
                    }
                    .codexActionButtonStyle()
                }
            }

            Section("Projects") {
                if self.workspaces.isEmpty {
                    Text("No projects for this host.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(self.workspaces) { workspace in
                        Button {
                            self.selectedWorkspaceID = workspace.id
                            self.selectedThreadID = nil
                            self.appState.hostSessionStore.selectProject(hostID: self.host.id, projectID: workspace.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(workspace.displayName)
                                        .font(.headline)
                                    Text(workspace.remotePath)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                if self.selectedWorkspaceID == workspace.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Delete", role: .destructive) {
                                self.appState.projectStore.delete(workspaceID: workspace.id)
                                if self.selectedWorkspaceID == workspace.id {
                                    self.selectedWorkspaceID = nil
                                    self.selectedThreadID = nil
                                    self.appState.hostSessionStore.selectProject(hostID: self.host.id, projectID: nil)
                                    self.appState.hostSessionStore.selectThread(hostID: self.host.id, threadID: nil)
                                }
                            }

                            Button("Edit") {
                                self.editingWorkspace = workspace
                                self.isPresentingProjectEditor = true
                            }
                            .tint(.orange)
                        }
                    }
                }

                Button {
                    self.editingWorkspace = nil
                    self.isPresentingProjectEditor = true
                } label: {
                    Label("Add Project", systemImage: "plus")
                }
                .codexActionButtonStyle()
            }

            Section("Threads") {
                if self.selectedWorkspace == nil {
                    Text("Select a project first.")
                        .foregroundStyle(.secondary)
                } else if self.threads.isEmpty {
                    Text("No threads for selected project.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(self.threads) { summary in
                        Button {
                            self.selectedThreadID = summary.threadID
                            self.appState.hostSessionStore.selectThread(hostID: self.host.id, threadID: summary.threadID)
                            self.loadThread(summary.threadID)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(summary.preview.isEmpty ? "(empty preview)" : summary.preview)
                                        .font(.subheadline)
                                        .lineLimit(2)
                                    Text(summary.threadID)
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
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(self.showArchived ? "Unarchive" : "Archive") {
                                self.archiveThread(summary: summary, archived: !self.showArchived)
                            }
                            .tint(self.showArchived ? .green : .blue)

                            Button("Delete", role: .destructive) {
                                self.appState.threadBookmarkStore.remove(threadID: summary.threadID, workspaceID: summary.workspaceID)
                                if self.selectedThreadID == summary.threadID {
                                    self.selectedThreadID = nil
                                    self.appState.hostSessionStore.selectThread(hostID: self.host.id, threadID: nil)
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
                    .disabled(self.appState.appServerClient.activeTurnID(for: self.selectedThreadID) == nil)
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
                            }
                        }
                    }
                }
            }

            Section("Transcript") {
                if let selectedThreadID,
                   !selectedThreadID.isEmpty {
                    Text(self.selectedThreadTranscript.isEmpty ? "No output yet." : self.selectedThreadTranscript)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Select thread to view output.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(self.host.name)
        .onAppear {
            self.appState.selectHost(self.host.id)
            self.appState.hostSessionStore.markOpened(hostID: self.host.id)
            self.restoreSelectionFromSession()
        }
        .onChange(of: self.showArchived) {
            self.refreshThreads()
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
        Task {
            do {
                try await self.appState.appServerClient.connect(to: self.host)
            } catch {
                self.localErrorMessage = self.appState.appServerClient.userFacingMessage(for: error)
            }
        }
    }

    private func refreshThreads() {
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
        self.appState.selectedTab = .terminal
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
