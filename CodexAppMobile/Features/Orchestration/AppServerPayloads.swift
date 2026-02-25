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
    let model: String?
    let reasoningEffort: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case preview
        case updatedAt
        case cwd
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
    let model: String?
    let reasoningEffort: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case turns
        case model
        case reasoningEffort
        case reasoningEffortSnake = "reasoning_effort"
        case effort
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.turns = try container.decodeIfPresent([ThreadReadTurnPayload].self, forKey: .turns) ?? []
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
