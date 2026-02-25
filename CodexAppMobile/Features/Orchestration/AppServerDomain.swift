import Foundation
import SwiftUI

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
    let model: String?
    let reasoningEffort: String?
}

struct AppServerModelDescriptor: Equatable, Identifiable {
    let model: String
    let displayName: String
    let reasoningEffortOptions: [CodexReasoningEffortOption]
    let defaultReasoningEffort: String?
    let isDefault: Bool

    var id: String { self.model }
}

struct AppServerCollaborationModeDescriptor: Equatable, Identifiable {
    let id: String
    let title: String
    let description: String?
    let isDefault: Bool

    var normalizedID: String {
        self.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum AppServerSlashCommandKind: String {
    case newThread
    case forkThread
    case startReview
    case startPlanMode
    case showStatus
}

struct AppServerSlashCommandDescriptor: Equatable, Identifiable {
    let kind: AppServerSlashCommandKind
    let command: String
    let title: String
    let description: String
    let systemImage: String
    let requiresThread: Bool

    var id: String { self.command }
}

struct AppServerMCPServerSummary: Equatable, Identifiable {
    let name: String
    let toolCount: Int
    let resourceCount: Int
    let authStatus: String?

    var id: String { self.name }
}

struct AppServerSkillSummary: Equatable, Identifiable {
    let name: String
    let path: String?
    let description: String?

    init(name: String, path: String?, description: String? = nil) {
        self.name = name
        self.path = path
        self.description = description
    }

    var id: String {
        if let path, !path.isEmpty {
            return path
        }
        return self.name
    }
}

struct AppServerAppSummary: Equatable, Identifiable {
    let slug: String
    let title: String

    var id: String { self.slug }
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

struct AppServerRateLimitSummary: Equatable, Identifiable {
    let name: String
    let usedPercent: Double?
    let remainingPercent: Double?
    let windowMinutes: Int?
    let resetsAt: Date?

    var id: String { "\(self.name)-\(self.windowMinutes ?? -1)" }
}

struct AppServerContextUsageSummary: Equatable {
    let usedTokens: Int?
    let maxTokens: Int?
    let remainingTokens: Int?
    let updatedAt: Date

    var remainingPercent: Double? {
        if let remainingTokens, let maxTokens, maxTokens > 0 {
            return max(0, min(100, (Double(remainingTokens) / Double(maxTokens)) * 100))
        }
        if let usedTokens, let maxTokens, maxTokens > 0 {
            return max(0, min(100, (Double(maxTokens - usedTokens) / Double(maxTokens)) * 100))
        }
        return nil
    }
}
