import Foundation

extension AppServerClient {
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

    static func parseModelCatalog(_ entries: [ModelListEntryPayload]) -> [AppServerModelDescriptor] {
        var models: [AppServerModelDescriptor] = []
        var seenModels: Set<String> = []

        for entry in entries {
            guard let model = Self.nonEmpty(entry.model ?? entry.id),
                  !seenModels.contains(model)
            else {
                continue
            }
            seenModels.insert(model)

            let displayName = Self.nonEmpty(entry.displayName) ?? model
            let defaultReasoningEffort = Self.normalizedReasoningEffort(entry.defaultReasoningEffort)

            var reasoningOptions: [CodexReasoningEffortOption] = []
            var seenEfforts: Set<String> = []
            for item in entry.reasoningEffort {
                guard let value = Self.normalizedReasoningEffort(item.effort),
                      !seenEfforts.contains(value) else {
                    continue
                }
                seenEfforts.insert(value)
                reasoningOptions.append(
                    CodexReasoningEffortOption(
                        value: value,
                        description: Self.nonEmpty(item.description)
                    )
                )
            }

            if let defaultReasoningEffort,
               !seenEfforts.contains(defaultReasoningEffort) {
                reasoningOptions.append(
                    CodexReasoningEffortOption(
                        value: defaultReasoningEffort,
                        description: nil
                    )
                )
            }

            models.append(
                AppServerModelDescriptor(
                    model: model,
                    displayName: displayName,
                    reasoningEffortOptions: reasoningOptions,
                    defaultReasoningEffort: defaultReasoningEffort,
                    isDefault: entry.isDefault
                )
            )
        }

        return models
    }

    static func parseCollaborationModeCatalog(_ result: JSONValue) -> [AppServerCollaborationModeDescriptor] {
        var rows = Self.dataArray(from: result, fallbackKeys: ["collaborationModes", "modes", "items"])

        if rows.isEmpty,
           let object = result.objectValue,
           let modesObject = object["collaborationModes"]?.objectValue ?? object["modes"]?.objectValue {
            rows = modesObject.map { modeID, value in
                if var modeObject = value.objectValue {
                    if Self.findString(
                        in: modeObject,
                        paths: [
                            ["id"],
                            ["slug"],
                            ["mode"],
                            ["name"],
                        ]
                    ) == nil {
                        modeObject["id"] = .string(modeID)
                    }
                    return .object(modeObject)
                }
                return .object(["id": .string(modeID)])
            }
        }

        var catalog: [AppServerCollaborationModeDescriptor] = []
        var seenIDs: Set<String> = []

        for row in rows {
            guard let object = row.objectValue else { continue }

            guard let modeID = Self.findString(
                in: object,
                paths: [
                    ["id"],
                    ["slug"],
                    ["mode"],
                    ["name"],
                ]
            ) else {
                continue
            }

            let normalizedID = modeID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalizedID.isEmpty,
                  seenIDs.insert(normalizedID).inserted else { continue }

            let title = Self.findString(
                in: object,
                paths: [
                    ["title"],
                    ["displayName"],
                    ["name"],
                    ["slug"],
                    ["id"],
                ]
            ) ?? modeID

            let description = Self.findString(
                in: object,
                paths: [
                    ["description"],
                    ["summary"],
                    ["prompt"],
                    ["helpText"],
                ]
            )

            let isDefault = Self.findBool(
                in: object,
                paths: [
                    ["isDefault"],
                    ["default"],
                    ["is_default"],
                ]
            ) ?? false

            catalog.append(
                AppServerCollaborationModeDescriptor(
                    id: modeID,
                    title: title,
                    description: Self.nonEmpty(description),
                    isDefault: isDefault
                )
            )
        }

        return catalog.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault {
                return lhs.isDefault && !rhs.isDefault
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    static func parseMCPServerCatalog(_ rows: [JSONValue]) -> [AppServerMCPServerSummary] {
        var catalog: [AppServerMCPServerSummary] = []
        var seenNames: Set<String> = []

        for row in rows {
            guard let object = row.objectValue else { continue }

            let name = Self.findString(
                in: object,
                paths: [
                    ["name"],
                    ["id"],
                    ["server", "name"],
                    ["serverName"],
                    ["displayName"],
                ]
            ) ?? "Unnamed MCP Server"

            guard !seenNames.contains(name) else { continue }
            seenNames.insert(name)

            let toolCount = object["toolCount"]?.intValue
                ?? object["toolsCount"]?.intValue
                ?? object["tools"]?.arrayValue?.count
                ?? 0
            let resourceCount = object["resourceCount"]?.intValue
                ?? object["resourcesCount"]?.intValue
                ?? object["resources"]?.arrayValue?.count
                ?? 0
            let authStatus = Self.findString(
                in: object,
                paths: [
                    ["authStatus"],
                    ["oauth", "status"],
                    ["status"],
                    ["auth", "status"],
                ]
            )

            catalog.append(
                AppServerMCPServerSummary(
                    name: name,
                    toolCount: toolCount,
                    resourceCount: resourceCount,
                    authStatus: authStatus
                )
            )
        }

        return catalog
    }

    static func parseSkillCatalog(_ entries: [JSONValue]) -> [AppServerSkillSummary] {
        var catalog: [AppServerSkillSummary] = []
        var seenIDs: Set<String> = []

        for entry in entries {
            guard let object = entry.objectValue else { continue }
            let skillRows: [JSONValue]
            if let skills = object["skills"]?.arrayValue {
                skillRows = skills
            } else if object["name"] != nil || object["path"] != nil {
                skillRows = [.object(object)]
            } else {
                skillRows = []
            }

            for skill in skillRows {
                guard let skillObject = skill.objectValue else { continue }
                let enabled = skillObject["enabled"]?.boolValue ?? true
                guard enabled else { continue }

                let name = Self.findString(
                    in: skillObject,
                    paths: [
                        ["name"],
                        ["interface", "displayName"],
                    ]
                ) ?? "Unnamed Skill"
                let path = Self.findString(
                    in: skillObject,
                    paths: [
                        ["path"],
                        ["source", "path"],
                    ]
                )
                let description = Self.findString(
                    in: skillObject,
                    paths: [
                        ["interface", "shortDescription"],
                        ["interface", "description"],
                        ["description"],
                        ["summary"],
                    ]
                )
                let id = path ?? name
                guard !seenIDs.contains(id) else { continue }
                seenIDs.insert(id)
                catalog.append(
                    AppServerSkillSummary(
                        name: name,
                        path: path,
                        description: Self.nonEmpty(description)
                    )
                )
            }
        }

        return catalog
    }

    static func parseAppCatalog(_ rows: [JSONValue]) -> [AppServerAppSummary] {
        var catalog: [AppServerAppSummary] = []
        var seenIDs: Set<String> = []

        for row in rows {
            guard let object = row.objectValue else { continue }
            let isAccessible = object["isAccessible"]?.boolValue ?? true
            guard isAccessible else { continue }

            guard let slug = Self.findString(in: object, paths: [["id"], ["slug"]]) else {
                continue
            }
            guard !seenIDs.contains(slug) else { continue }
            seenIDs.insert(slug)

            let title = Self.findString(in: object, paths: [["name"], ["title"]]) ?? slug
            catalog.append(AppServerAppSummary(slug: slug, title: title))
        }

        return catalog
    }

    static func parseRateLimitCatalog(_ result: JSONValue) -> [AppServerRateLimitSummary] {
        var catalog: [AppServerRateLimitSummary] = []
        var seenIDs: Set<String> = []

        guard let object = result.objectValue else {
            return []
        }

        if let byLimitID = object["rateLimitsByLimitId"]?.objectValue
            ?? object["rate_limits_by_limit_id"]?.objectValue,
           !byLimitID.isEmpty {
            for limitID in byLimitID.keys.sorted() {
                guard let limitObject = byLimitID[limitID]?.objectValue else { continue }
                let limitName = Self.findString(
                    in: limitObject,
                    paths: [
                        ["limitName"],
                        ["limit_name"],
                        ["name"],
                        ["label"],
                        ["limitId"],
                        ["limit_id"],
                        ["id"],
                    ]
                ) ?? limitID
                for summary in Self.parseRateLimitSummaries(in: limitObject, limitName: limitName) {
                    let id = "\(summary.name.lowercased())-\(summary.windowMinutes ?? -1)"
                    guard seenIDs.insert(id).inserted else { continue }
                    catalog.append(summary)
                }
            }
        }

        if let rateLimitsObject = object["rateLimits"]?.objectValue
            ?? object["rate_limits"]?.objectValue {
            let limitName = Self.findString(
                in: rateLimitsObject,
                paths: [
                    ["limitName"],
                    ["limit_name"],
                    ["name"],
                    ["label"],
                    ["limitId"],
                    ["limit_id"],
                    ["id"],
                ]
            ) ?? "Limit"
            for summary in Self.parseRateLimitSummaries(in: rateLimitsObject, limitName: limitName) {
                let id = "\(summary.name.lowercased())-\(summary.windowMinutes ?? -1)"
                guard seenIDs.insert(id).inserted else { continue }
                catalog.append(summary)
            }
        }

        if catalog.isEmpty {
            let rows = Self.dataArray(from: result, fallbackKeys: ["rateLimits", "limits", "items"])
            for row in rows {
                guard let itemObject = row.objectValue else { continue }
                let limitName = Self.findString(
                    in: itemObject,
                    paths: [
                        ["limitName"],
                        ["limit_name"],
                        ["name"],
                        ["label"],
                        ["id"],
                    ]
                ) ?? "Limit"
                for summary in Self.parseRateLimitSummaries(in: itemObject, limitName: limitName) {
                    let id = "\(summary.name.lowercased())-\(summary.windowMinutes ?? -1)"
                    guard seenIDs.insert(id).inserted else { continue }
                    catalog.append(summary)
                }
            }
        }

        return catalog
    }

    static func parseRateLimitSummaries(
        in object: [String: JSONValue],
        limitName: String
    ) -> [AppServerRateLimitSummary] {
        var summaries: [AppServerRateLimitSummary] = []

        if let primaryObject = object["primary"]?.objectValue,
           let summary = Self.parseSingleRateLimitSummary(in: primaryObject, limitName: limitName) {
            summaries.append(summary)
        }

        if let secondaryObject = object["secondary"]?.objectValue,
           let summary = Self.parseSingleRateLimitSummary(in: secondaryObject, limitName: limitName) {
            summaries.append(summary)
        }

        if summaries.isEmpty,
           let summary = Self.parseSingleRateLimitSummary(in: object, limitName: limitName) {
            summaries.append(summary)
        }

        return summaries
    }

    static func parseSingleRateLimitSummary(
        in object: [String: JSONValue],
        limitName: String
    ) -> AppServerRateLimitSummary? {
        let windowMinutes = Self.findInt(
            in: object,
            paths: [
                ["windowDurationMins"],
                ["window_duration_mins"],
                ["windowMinutes"],
                ["window_minutes"],
                ["window", "minutes"],
                ["window"],
            ]
        )

        var usedPercent = Self.findDouble(
            in: object,
            paths: [
                ["usedPercent"],
                ["used_percent"],
                ["usage", "usedPercent"],
                ["used_percentage"],
            ]
        )
        if usedPercent == nil,
           let used = Self.findDouble(in: object, paths: [["used"], ["usage", "used"]]),
           let total = Self.findDouble(in: object, paths: [["total"], ["limit"], ["max"], ["usage", "limit"], ["usage", "max"]]),
           total > 0 {
            usedPercent = (used / total) * 100
        }

        var remainingPercent = Self.findDouble(
            in: object,
            paths: [
                ["remainingPercent"],
                ["remaining_percent"],
                ["leftPercent"],
                ["usage", "remainingPercent"],
            ]
        )
        if remainingPercent == nil,
           let remaining = Self.findDouble(in: object, paths: [["remaining"], ["usage", "remaining"]]),
           let total = Self.findDouble(in: object, paths: [["total"], ["limit"], ["max"], ["usage", "limit"], ["usage", "max"]]),
           total > 0 {
            remainingPercent = (remaining / total) * 100
        }

        if let currentUsedPercent = usedPercent, currentUsedPercent <= 1 {
            usedPercent = currentUsedPercent * 100
        }
        if let currentUsedPercent = usedPercent {
            usedPercent = max(0, min(100, currentUsedPercent))
        }

        if let currentRemainingPercent = remainingPercent, currentRemainingPercent <= 1 {
            remainingPercent = currentRemainingPercent * 100
        }
        if remainingPercent == nil, let usedPercent {
            remainingPercent = max(0, 100 - usedPercent)
        }
        if let currentRemainingPercent = remainingPercent {
            remainingPercent = max(0, min(100, currentRemainingPercent))
        }

        let resetsAt = Self.findDate(
            in: object,
            paths: [
                ["resetsAt"],
                ["resetAt"],
                ["resets_at"],
                ["resetsAtUnixSeconds"],
                ["resetAtUnixSeconds"],
                ["resetsAtEpochSeconds"],
                ["resetAtEpochSeconds"],
                ["resets_at_unix_seconds"],
                ["reset_at_unix_seconds"],
            ]
        )

        if usedPercent == nil, remainingPercent == nil, windowMinutes == nil, resetsAt == nil {
            return nil
        }

        return AppServerRateLimitSummary(
            name: limitName,
            usedPercent: usedPercent,
            remainingPercent: remainingPercent,
            windowMinutes: windowMinutes,
            resetsAt: resetsAt
        )
    }

    static func findDate(in object: [String: JSONValue], paths: [[String]]) -> Date? {
        for path in paths {
            guard let value = Self.value(at: path, in: object),
                  let parsed = Self.parseRateLimitDate(value) else {
                continue
            }
            return parsed
        }
        return nil
    }

    static func parseRateLimitDate(_ raw: JSONValue) -> Date? {
        switch raw {
        case .number(let seconds):
            return Date(timeIntervalSince1970: seconds)
        case .string(let value):
            return Self.parseRateLimitDate(value)
        default:
            return nil
        }
    }

    static func parseRateLimitDate(_ raw: String) -> Date? {
        if let seconds = TimeInterval(raw) {
            return Date(timeIntervalSince1970: seconds)
        }
        if let date = Self.iso8601WithFractional.date(from: raw) {
            return date
        }
        if let date = Self.iso8601Basic.date(from: raw) {
            return date
        }
        return nil
    }

    static func dataArray(from result: JSONValue, fallbackKeys: [String] = []) -> [JSONValue] {
        guard let object = result.objectValue else { return [] }
        if let data = object["data"]?.arrayValue {
            return data
        }
        for key in fallbackKeys {
            if let rows = object[key]?.arrayValue {
                return rows
            }
        }
        return []
    }

    static func nextCursor(from result: JSONValue) -> String? {
        guard let object = result.objectValue else { return nil }
        return Self.findString(
            in: object,
            paths: [
                ["nextCursor"],
                ["next_cursor"],
                ["cursor"],
            ]
        )
    }

    static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func normalizedReasoningEffort(_ raw: String?) -> String? {
        guard let raw = Self.nonEmpty(raw) else { return nil }
        return raw.lowercased()
    }

    static func collaborationModePayload(for rawModeID: String) -> JSONValue? {
        guard let modeID = Self.nonEmpty(rawModeID) else {
            return nil
        }
        return .object([
            "id": .string(modeID)
        ])
    }

    static func shouldRetryWithoutEffort(_ error: Error) -> Bool {
        guard case let AppServerClientError.remote(code, message) = error else {
            return false
        }
        let normalized = message.lowercased()
        return code == -32602
            || normalized.contains("invalid params")
            || normalized.contains("reasoning")
            || normalized.contains("effort")
            || normalized.contains("unknown field")
    }

    static func shouldRetryWithoutModel(_ error: Error) -> Bool {
        guard case let AppServerClientError.remote(code, message) = error else {
            return false
        }
        let normalized = message.lowercased()
        return code == -32602
            || normalized.contains("invalid params")
            || normalized.contains("model")
            || normalized.contains("unknown field")
    }

    static func shouldRetryWithoutCollaborationMode(_ error: Error) -> Bool {
        guard case let AppServerClientError.remote(code, message) = error else {
            return false
        }
        let normalized = message.lowercased()
        return code == -32602
            || normalized.contains("invalid params")
            || normalized.contains("unknown field")
            || normalized.contains("collaborationmode")
            || normalized.contains("collaboration mode")
    }

    static func shouldRetryReviewStartTarget(_ error: Error) -> Bool {
        guard case let AppServerClientError.remote(code, message) = error else {
            return false
        }
        let normalized = message.lowercased()
        return code == -32602
            || normalized.contains("invalid params")
            || normalized.contains("unknown field")
    }

    func nonEmptyOrNil(_ value: String) -> String? {
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

    static func versionComponents(_ rawVersion: String) -> [Int] {
        let matches = rawVersion.matches(of: /(\d+)/)
        return matches.compactMap { Int($0.output.1) }
    }

    static func findString(in object: [String: JSONValue], paths: [[String]]) -> String? {
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

    static func findRawString(in object: [String: JSONValue], paths: [[String]]) -> String? {
        for path in paths {
            guard let value = Self.value(at: path, in: object),
                  let stringValue = value.stringValue,
                  stringValue.isEmpty == false
            else {
                continue
            }
            return stringValue
        }
        return nil
    }

    static func findInt(in object: [String: JSONValue], paths: [[String]]) -> Int? {
        for path in paths {
            if let value = Self.value(at: path, in: object)?.intValue {
                return value
            }
        }
        return nil
    }

    static func findDouble(in object: [String: JSONValue], paths: [[String]]) -> Double? {
        for path in paths {
            guard let value = Self.value(at: path, in: object) else { continue }
            switch value {
            case .number(let number):
                return number
            case .string(let string):
                if let parsed = Double(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    return parsed
                }
            default:
                break
            }
        }
        return nil
    }

    static func findBool(in object: [String: JSONValue], paths: [[String]]) -> Bool? {
        for path in paths {
            guard let value = Self.value(at: path, in: object) else { continue }
            switch value {
            case .bool(let boolValue):
                return boolValue
            case .string(let string):
                let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if normalized == "true" || normalized == "1" || normalized == "yes" {
                    return true
                }
                if normalized == "false" || normalized == "0" || normalized == "no" {
                    return false
                }
            case .number(let number):
                return number != 0
            default:
                break
            }
        }
        return nil
    }

    static func value(at path: [String], in object: [String: JSONValue]) -> JSONValue? {
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

    static let iso8601WithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let iso8601Basic: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func isUnroutableEndpointHost(_ host: String) -> Bool {
        switch host.lowercased() {
        case "0.0.0.0", "::", "::1", "localhost", "127.0.0.1":
            return true
        default:
            return false
        }
    }

    static func errorCategory(for error: Error) -> AppServerErrorCategory {
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

    func preferredUserFacingMessage(for error: Error) -> String? {
        guard let urlError = error as? URLError,
              urlError.code == .networkConnectionLost,
              !self.hasReceivedMessageOnCurrentConnection
        else {
            return nil
        }

        return "[Connection] WebSocket handshake failed before app-server initialization. codex app-server may reject iOS WebSocket extension negotiation (Sec-WebSocket-Extensions). Run scripts/ws_strip_extensions_proxy.js on the remote host and connect iOS to that proxy URL, or use Terminal tab."
    }

    func shouldAttemptReconnect(after error: Error) -> Bool {
        guard let urlError = error as? URLError else {
            return true
        }

        if urlError.code == .networkConnectionLost,
           !self.hasReceivedMessageOnCurrentConnection {
            return false
        }

        return true
    }

    static func errorCategoryFromRemote(code: Int, message: String) -> AppServerErrorCategory {
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

    func decode<T: Decodable>(_ value: JSONValue, as type: T.Type) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(type, from: data)
    }

    func convertThread(
        _ thread: ThreadReadThreadPayload,
        modelOverride: String? = nil,
        reasoningEffortOverride: String? = nil
    ) -> CodexThreadDetail {
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

            return CodexTurn(
                id: turn.id,
                status: turn.status,
                items: items,
                model: Self.nonEmpty(turn.model),
                reasoningEffort: Self.normalizedReasoningEffort(turn.reasoningEffort)
            )
        }

        let resolvedThreadModel = Self.nonEmpty(modelOverride) ?? Self.nonEmpty(thread.model)
        let resolvedThreadReasoningEffort = Self.normalizedReasoningEffort(reasoningEffortOverride)
            ?? Self.normalizedReasoningEffort(thread.reasoningEffort)

        return CodexThreadDetail(
            threadID: thread.id,
            turns: turns,
            model: resolvedThreadModel,
            reasoningEffort: resolvedThreadReasoningEffort
        )
    }

    static func renderThread(_ detail: CodexThreadDetail) -> String {
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
}

extension URLSessionWebSocketTask {
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
