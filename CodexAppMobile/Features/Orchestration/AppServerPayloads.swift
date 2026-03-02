import Foundation

struct ThreadListResponsePayload: Decodable {
    let data: [ThreadListEntryPayload]
}

struct ModelListResponsePayload: Decodable {
    let data: [ModelListEntryPayload]
    let nextCursor: String?

    private enum CodingKeys: String, CodingKey {
        case data
        case nextCursor
        case nextCursorSnake = "next_cursor"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.data = try container.decodeIfPresent([ModelListEntryPayload].self, forKey: .data) ?? []
        self.nextCursor = try container.decodeIfPresent(String.self, forKey: .nextCursor)
            ?? container.decodeIfPresent(String.self, forKey: .nextCursorSnake)
    }
}

struct ModelListEntryPayload: Decodable {
    let id: String?
    let model: String?
    let displayName: String?
    let reasoningEffort: [ModelReasoningEffortPayload]
    let defaultReasoningEffort: String?
    let isDefault: Bool
    let upgradeInfo: ModelUpgradeInfoPayload?
    let availabilityNuxMessage: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case model
        case displayName
        case name
        case reasoningEffort
        case reasoningEffortSnake = "reasoning_effort"
        case supportedReasoningEfforts
        case supportedReasoningEffortsSnake = "supported_reasoning_efforts"
        case defaultReasoningEffort
        case defaultReasoningEffortSnake = "default_reasoning_effort"
        case isDefault
        case upgradeInfo
        case upgradeInfoSnake = "upgrade_info"
        case availabilityNux
        case availabilityNuxSnake = "availability_nux"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
        self.model = try container.decodeIfPresent(String.self, forKey: .model)
        self.displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
            ?? container.decodeIfPresent(String.self, forKey: .name)
        self.reasoningEffort = try Self.decodeReasoningEffortOptions(from: container, key: .reasoningEffort)
            ?? Self.decodeReasoningEffortOptions(from: container, key: .reasoningEffortSnake)
            ?? Self.decodeReasoningEffortOptions(from: container, key: .supportedReasoningEfforts)
            ?? Self.decodeReasoningEffortOptions(from: container, key: .supportedReasoningEffortsSnake)
            ?? []
        self.defaultReasoningEffort = try container.decodeIfPresent(String.self, forKey: .defaultReasoningEffort)
            ?? container.decodeIfPresent(String.self, forKey: .defaultReasoningEffortSnake)
        self.isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        self.upgradeInfo = try container.decodeIfPresent(ModelUpgradeInfoPayload.self, forKey: .upgradeInfo)
            ?? container.decodeIfPresent(ModelUpgradeInfoPayload.self, forKey: .upgradeInfoSnake)
        let availabilityNux = try container.decodeIfPresent(ModelAvailabilityNuxPayload.self, forKey: .availabilityNux)
            ?? container.decodeIfPresent(ModelAvailabilityNuxPayload.self, forKey: .availabilityNuxSnake)
        self.availabilityNuxMessage = availabilityNux?.message
    }

    private static func decodeReasoningEffortOptions(
        from container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) throws -> [ModelReasoningEffortPayload]? {
        do {
            if let options = try container.decodeIfPresent([ModelReasoningEffortPayload].self, forKey: key) {
                return options
            }
        } catch DecodingError.typeMismatch {
            // Fallback to legacy string-array shape below.
        }
        if let values = try container.decodeIfPresent([String].self, forKey: key) {
            return values.map { ModelReasoningEffortPayload(effort: $0, description: nil) }
        }
        return nil
    }
}

struct ModelUpgradeInfoPayload: Decodable {
    let model: String
    let upgradeCopy: String?
    let modelLink: String?
    let migrationMarkdown: String?

    private enum CodingKeys: String, CodingKey {
        case model
        case upgradeCopy
        case upgradeCopySnake = "upgrade_copy"
        case modelLink
        case modelLinkSnake = "model_link"
        case migrationMarkdown
        case migrationMarkdownSnake = "migration_markdown"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.model = try container.decode(String.self, forKey: .model)
        self.upgradeCopy = try container.decodeIfPresent(String.self, forKey: .upgradeCopy)
            ?? container.decodeIfPresent(String.self, forKey: .upgradeCopySnake)
        self.modelLink = try container.decodeIfPresent(String.self, forKey: .modelLink)
            ?? container.decodeIfPresent(String.self, forKey: .modelLinkSnake)
        self.migrationMarkdown = try container.decodeIfPresent(String.self, forKey: .migrationMarkdown)
            ?? container.decodeIfPresent(String.self, forKey: .migrationMarkdownSnake)
    }
}

struct ModelAvailabilityNuxPayload: Decodable {
    let message: String
}

struct ModelReasoningEffortPayload: Decodable {
    let effort: String
    let description: String?

    init(effort: String, description: String?) {
        self.effort = effort
        self.description = description
    }

    private enum CodingKeys: String, CodingKey {
        case effort
        case reasoningEffort
        case reasoningEffortSnake = "reasoning_effort"
        case id
        case value
        case name
        case description
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.effort = try container.decodeIfPresent(String.self, forKey: .effort)
            ?? container.decodeIfPresent(String.self, forKey: .reasoningEffort)
            ?? container.decodeIfPresent(String.self, forKey: .reasoningEffortSnake)
            ?? container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .value)
            ?? container.decodeIfPresent(String.self, forKey: .name)
            ?? ""
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
    }
}

struct ThreadListEntryPayload: Decodable {
    let id: String
    let preview: String
    let updatedAt: Int
    let cwd: String
    let ephemeral: Bool
    let model: String?
    let reasoningEffort: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case preview
        case updatedAt
        case cwd
        case ephemeral
        case model
        case reasoningEffort
        case reasoningEffortSnake = "reasoning_effort"
        case effort
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.preview = try container.decode(String.self, forKey: .preview)
        self.updatedAt = try container.decode(Int.self, forKey: .updatedAt)
        self.cwd = try container.decodeIfPresent(String.self, forKey: .cwd) ?? ""
        self.ephemeral = try container.decodeIfPresent(Bool.self, forKey: .ephemeral) ?? false
        self.model = try container.decodeIfPresent(String.self, forKey: .model)
        self.reasoningEffort = try container.decodeIfPresent(String.self, forKey: .reasoningEffort)
            ?? container.decodeIfPresent(String.self, forKey: .reasoningEffortSnake)
            ?? container.decodeIfPresent(String.self, forKey: .effort)
    }
}

struct ThreadLifecycleResponsePayload: Decodable {
    let thread: ThreadIDPayload
}

struct ThreadIDPayload: Decodable {
    let id: String
    let ephemeral: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case ephemeral
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.ephemeral = try container.decodeIfPresent(Bool.self, forKey: .ephemeral) ?? false
    }
}

struct TurnStartResponsePayload: Decodable {
    let turn: TurnIDPayload
}

struct TurnIDPayload: Decodable {
    let id: String
}

struct ThreadReadResponsePayload: Decodable {
    let thread: ThreadReadThreadPayload
    let model: String?
    let reasoningEffort: String?

    private enum CodingKeys: String, CodingKey {
        case thread
        case model
        case reasoningEffort
        case reasoningEffortSnake = "reasoning_effort"
        case effort
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.thread = try container.decode(ThreadReadThreadPayload.self, forKey: .thread)
        self.model = try container.decodeIfPresent(String.self, forKey: .model)
        self.reasoningEffort = try container.decodeIfPresent(String.self, forKey: .reasoningEffort)
            ?? container.decodeIfPresent(String.self, forKey: .reasoningEffortSnake)
            ?? container.decodeIfPresent(String.self, forKey: .effort)
    }
}

struct ThreadResumeResponsePayload: Decodable {
    let thread: ThreadReadThreadPayload
    let model: String?
    let reasoningEffort: String?

    private enum CodingKeys: String, CodingKey {
        case thread
        case model
        case reasoningEffort
        case reasoningEffortSnake = "reasoning_effort"
        case effort
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.thread = try container.decode(ThreadReadThreadPayload.self, forKey: .thread)
        self.model = try container.decodeIfPresent(String.self, forKey: .model)
        self.reasoningEffort = try container.decodeIfPresent(String.self, forKey: .reasoningEffort)
            ?? container.decodeIfPresent(String.self, forKey: .reasoningEffortSnake)
            ?? container.decodeIfPresent(String.self, forKey: .effort)
    }
}

struct ThreadReadThreadPayload: Decodable {
    let id: String
    let turns: [ThreadReadTurnPayload]
    let ephemeral: Bool
    let model: String?
    let reasoningEffort: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case turns
        case ephemeral
        case model
        case reasoningEffort
        case reasoningEffortSnake = "reasoning_effort"
        case effort
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.turns = try container.decodeIfPresent([ThreadReadTurnPayload].self, forKey: .turns) ?? []
        self.ephemeral = try container.decodeIfPresent(Bool.self, forKey: .ephemeral) ?? false
        self.model = try container.decodeIfPresent(String.self, forKey: .model)
        self.reasoningEffort = try container.decodeIfPresent(String.self, forKey: .reasoningEffort)
            ?? container.decodeIfPresent(String.self, forKey: .reasoningEffortSnake)
            ?? container.decodeIfPresent(String.self, forKey: .effort)
    }
}

struct ThreadReadTurnPayload: Decodable {
    let id: String
    let status: String
    let items: [ThreadReadItemPayload]
    let model: String?
    let reasoningEffort: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case status
        case items
        case model
        case reasoningEffort
        case reasoningEffortSnake = "reasoning_effort"
        case effort
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.status = try container.decode(String.self, forKey: .status)
        self.items = try container.decodeIfPresent([ThreadReadItemPayload].self, forKey: .items) ?? []
        self.model = try container.decodeIfPresent(String.self, forKey: .model)
        self.reasoningEffort = try container.decodeIfPresent(String.self, forKey: .reasoningEffort)
            ?? container.decodeIfPresent(String.self, forKey: .reasoningEffortSnake)
            ?? container.decodeIfPresent(String.self, forKey: .effort)
    }
}

struct ThreadReadItemPayload: Decodable {
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

struct ThreadReadFileChangePayload: Decodable {
    let path: String?
}

struct ThreadReadUserInputPayload: Decodable {
    let type: String
    let text: String?
    let path: String?
    let name: String?
}

struct AccountUpdatedNotificationPayload: Decodable {
    let authMode: String?
    let planType: String?

    private enum CodingKeys: String, CodingKey {
        case authMode
        case authModeSnake = "auth_mode"
        case planType
        case planTypeSnake = "plan_type"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.authMode = try container.decodeIfPresent(String.self, forKey: .authMode)
            ?? container.decodeIfPresent(String.self, forKey: .authModeSnake)
        self.planType = try container.decodeIfPresent(String.self, forKey: .planType)
            ?? container.decodeIfPresent(String.self, forKey: .planTypeSnake)
    }
}

struct ServerRequestResolvedNotificationPayload: Decodable {
    let threadID: String
    let requestID: JSONValue

    private enum CodingKeys: String, CodingKey {
        case threadID
        case threadIDSnake = "thread_id"
        case requestID
        case requestIDSnake = "request_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.threadID = try container.decodeIfPresent(String.self, forKey: .threadID)
            ?? container.decodeIfPresent(String.self, forKey: .threadIDSnake)
            ?? ""
        self.requestID = try container.decodeIfPresent(JSONValue.self, forKey: .requestID)
            ?? container.decodeIfPresent(JSONValue.self, forKey: .requestIDSnake)
            ?? .null
    }
}

struct CommandExecutionRequestApprovalPayload: Decodable {
    let threadID: String
    let turnID: String
    let itemID: String
    let command: String?
    let cwd: String?
    let reason: String?
    let networkApprovalContext: CommandNetworkApprovalContextPayload?
    let additionalPermissions: CommandAdditionalPermissionsPayload?
    let proposedExecPolicyAmendment: CommandExecPolicyAmendmentPayload?
    let proposedNetworkPolicyAmendments: [CommandNetworkPolicyAmendmentPayload]
    let availableDecisions: [CommandExecutionApprovalDecisionPayload]

    private enum CodingKeys: String, CodingKey {
        case threadID
        case threadIDSnake = "thread_id"
        case turnID
        case turnIDSnake = "turn_id"
        case itemID
        case itemIDSnake = "item_id"
        case command
        case cwd
        case reason
        case networkApprovalContext
        case networkApprovalContextSnake = "network_approval_context"
        case additionalPermissions
        case additionalPermissionsSnake = "additional_permissions"
        case proposedExecPolicyAmendment
        case proposedExecPolicyAmendmentSnake = "proposed_execpolicy_amendment"
        case proposedNetworkPolicyAmendments
        case proposedNetworkPolicyAmendmentsSnake = "proposed_network_policy_amendments"
        case availableDecisions
        case availableDecisionsSnake = "available_decisions"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.threadID = try container.decodeIfPresent(String.self, forKey: .threadID)
            ?? container.decodeIfPresent(String.self, forKey: .threadIDSnake)
            ?? ""
        self.turnID = try container.decodeIfPresent(String.self, forKey: .turnID)
            ?? container.decodeIfPresent(String.self, forKey: .turnIDSnake)
            ?? ""
        self.itemID = try container.decodeIfPresent(String.self, forKey: .itemID)
            ?? container.decodeIfPresent(String.self, forKey: .itemIDSnake)
            ?? ""
        self.command = try container.decodeIfPresent(String.self, forKey: .command)
        self.cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        self.reason = try container.decodeIfPresent(String.self, forKey: .reason)
        self.networkApprovalContext = try container.decodeIfPresent(CommandNetworkApprovalContextPayload.self, forKey: .networkApprovalContext)
            ?? container.decodeIfPresent(CommandNetworkApprovalContextPayload.self, forKey: .networkApprovalContextSnake)
        self.additionalPermissions = try container.decodeIfPresent(CommandAdditionalPermissionsPayload.self, forKey: .additionalPermissions)
            ?? container.decodeIfPresent(CommandAdditionalPermissionsPayload.self, forKey: .additionalPermissionsSnake)
        self.proposedExecPolicyAmendment = try container.decodeIfPresent(CommandExecPolicyAmendmentPayload.self, forKey: .proposedExecPolicyAmendment)
            ?? container.decodeIfPresent(CommandExecPolicyAmendmentPayload.self, forKey: .proposedExecPolicyAmendmentSnake)
        self.proposedNetworkPolicyAmendments = try container.decodeIfPresent([CommandNetworkPolicyAmendmentPayload].self, forKey: .proposedNetworkPolicyAmendments)
            ?? container.decodeIfPresent([CommandNetworkPolicyAmendmentPayload].self, forKey: .proposedNetworkPolicyAmendmentsSnake)
            ?? []
        self.availableDecisions = try container.decodeIfPresent([CommandExecutionApprovalDecisionPayload].self, forKey: .availableDecisions)
            ?? container.decodeIfPresent([CommandExecutionApprovalDecisionPayload].self, forKey: .availableDecisionsSnake)
            ?? []
    }
}

struct CommandNetworkApprovalContextPayload: Decodable {
    let host: String
    let `protocol`: String?
}

struct CommandAdditionalPermissionsPayload: Decodable {
    let network: Bool?
    let fileSystem: CommandAdditionalFileSystemPermissionsPayload?

    private enum CodingKeys: String, CodingKey {
        case network
        case fileSystem
        case fileSystemSnake = "file_system"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.network = try container.decodeIfPresent(Bool.self, forKey: .network)
        self.fileSystem = try container.decodeIfPresent(CommandAdditionalFileSystemPermissionsPayload.self, forKey: .fileSystem)
            ?? container.decodeIfPresent(CommandAdditionalFileSystemPermissionsPayload.self, forKey: .fileSystemSnake)
    }
}

struct CommandAdditionalFileSystemPermissionsPayload: Decodable {
    let read: [String]?
    let write: [String]?
}

struct CommandExecPolicyAmendmentPayload: Decodable {
    let command: [String]
}

struct CommandNetworkPolicyAmendmentPayload: Decodable {
    let host: String
    let action: String
}

enum CommandExecutionApprovalDecisionPayload: Decodable {
    case accept
    case acceptForSession
    case acceptWithExecpolicyAmendment(amendment: CommandExecPolicyAmendmentPayload?)
    case applyNetworkPolicyAmendment(amendment: CommandNetworkPolicyAmendmentPayload?)
    case decline
    case cancel
    case unknown

    init(from decoder: Decoder) throws {
        if let singleValue = try? decoder.singleValueContainer(),
           let raw = try? singleValue.decode(String.self) {
            let normalized = raw
                .replacingOccurrences(of: "_", with: "")
                .replacingOccurrences(of: "-", with: "")
                .lowercased()
            switch normalized {
                case "accept":
                    self = .accept
                case "acceptforsession":
                    self = .acceptForSession
                case "decline":
                    self = .decline
            case "cancel":
                self = .cancel
            default:
                self = .unknown
            }
            return
        }

        let container = try decoder.singleValueContainer()
        let object = try container.decode([String: JSONValue].self)
        if let raw = object["acceptWithExecpolicyAmendment"]?.objectValue
            ?? object["accept_with_execpolicy_amendment"]?.objectValue {
            let amendment = raw["execpolicy_amendment"]?.arrayValue?.compactMap(\.stringValue)
            self = .acceptWithExecpolicyAmendment(
                amendment: amendment.map { CommandExecPolicyAmendmentPayload(command: $0) }
            )
            return
        }
        if let raw = object["applyNetworkPolicyAmendment"]?.objectValue
            ?? object["apply_network_policy_amendment"]?.objectValue {
            let amendmentObject = raw["network_policy_amendment"]?.objectValue
            let host = amendmentObject?["host"]?.stringValue
            let action = amendmentObject?["action"]?.stringValue
            if let host, let action {
                self = .applyNetworkPolicyAmendment(
                    amendment: CommandNetworkPolicyAmendmentPayload(host: host, action: action)
                )
            } else {
                self = .applyNetworkPolicyAmendment(amendment: nil)
            }
            return
        }
        self = .unknown
    }
}
