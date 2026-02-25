import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

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

struct CodexReasoningEffortOption: Equatable, Identifiable {
    let value: String
    let description: String?

    var id: String { self.value }

    var displayName: String {
        let trimmed = self.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else {
            return "Reasoning"
        }
        return first.uppercased() + trimmed.dropFirst()
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
        let trimmedName = self.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            return trimmedName
        }

        let trimmedPath = self.remotePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedPath == "/" || trimmedPath == "~" {
            return trimmedPath
        }

        let normalizedPath = trimmedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if let lastComponent = normalizedPath.split(separator: "/").last,
           !lastComponent.isEmpty {
            return String(lastComponent)
        }

        return trimmedPath
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
    var model: String?
    var reasoningEffort: String?

    private enum CodingKeys: String, CodingKey {
        case threadID
        case hostID
        case connectionID
        case workspaceID
        case preview
        case updatedAt
        case archived
        case cwd
        case model
        case reasoningEffort
        case reasoningEffortSnake = "reasoning_effort"
    }

    init(
        threadID: String,
        hostID: UUID,
        workspaceID: UUID,
        preview: String,
        updatedAt: Date,
        archived: Bool,
        cwd: String,
        model: String? = nil,
        reasoningEffort: String? = nil
    ) {
        self.threadID = threadID
        self.hostID = hostID
        self.workspaceID = workspaceID
        self.preview = preview
        self.updatedAt = updatedAt
        self.archived = archived
        self.cwd = cwd
        self.model = Self.normalizedValue(model)
        self.reasoningEffort = Self.normalizedReasoningEffort(reasoningEffort)
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
        self.model = Self.normalizedValue(try container.decodeIfPresent(String.self, forKey: .model))
        self.reasoningEffort = Self.normalizedReasoningEffort(
            try container.decodeIfPresent(String.self, forKey: .reasoningEffort)
                ?? container.decodeIfPresent(String.self, forKey: .reasoningEffortSnake)
        )
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
        try container.encodeIfPresent(Self.normalizedValue(self.model), forKey: .model)
        try container.encodeIfPresent(Self.normalizedReasoningEffort(self.reasoningEffort), forKey: .reasoningEffort)
    }

    private static func normalizedValue(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedReasoningEffort(_ raw: String?) -> String? {
        guard let normalized = Self.normalizedValue(raw) else { return nil }
        return normalized.lowercased()
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
    let model: String?
    let reasoningEffort: String?
}

struct CodexThreadDetail: Equatable {
    let threadID: String
    let turns: [CodexTurn]
    let model: String?
    let reasoningEffort: String?
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
