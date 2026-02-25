import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class AppServerClient: ObservableObject {
    static let minimumSupportedCLIVersion = "0.101.0"

    enum State: String {
        case disconnected
        case connecting
        case connected
    }

    enum TurnStreamingPhase: String, Equatable {
        case thinking
        case responding
    }

    /// Called on the main actor when a turn completes.
    /// Parameters: threadID, status, response snippet (first ~200 chars of the transcript delta).
    var onTurnCompleted: ((_ threadID: String, _ status: String, _ responseSnippet: String) -> Void)?

    @Published private(set) var state: State = .disconnected
    @Published private(set) var lastErrorMessage = ""
    @Published private(set) var connectedEndpoint = ""
    @Published private(set) var pendingRequests: [AppServerPendingRequest] = []
    @Published private(set) var transcriptByThread: [String: String] = [:]
    @Published private(set) var activeTurnIDByThread: [String: String] = [:]
    @Published private(set) var turnStreamingPhaseByThread: [String: TurnStreamingPhase] = [:]
    @Published private(set) var availableModels: [AppServerModelDescriptor] = []
    @Published private(set) var availableCollaborationModes: [AppServerCollaborationModeDescriptor] = []
    @Published private(set) var mcpServers: [AppServerMCPServerSummary] = []
    @Published private(set) var availableSkills: [AppServerSkillSummary] = []
    @Published private(set) var availableApps: [AppServerAppSummary] = []
    @Published private(set) var availableSlashCommands: [AppServerSlashCommandDescriptor] = []
    @Published private(set) var rateLimits: [AppServerRateLimitSummary] = []
    @Published private(set) var contextUsageByThread: [String: AppServerContextUsageSummary] = [:]
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
    private var streamedItemPrefixKeys: Set<String> = []
    /// Tracks the transcript snapshot before a turn starts so we can extract the response delta.
    private var transcriptSnapshotBeforeTurn: [String: String] = [:]

    private let requestTimeoutSeconds: TimeInterval = 30
    private let overloadRetryMaxAttempts = 4

    #if canImport(UIKit)
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    #endif

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Request extended background execution while active turns are in progress.
    /// Call when the app transitions to background and there are pending turns.
    func beginBackgroundProcessingIfNeeded() {
        #if canImport(UIKit)
        guard self.backgroundTaskID == .invalid,
              !self.activeTurnIDByThread.isEmpty else { return }
        self.backgroundTaskID = UIApplication.shared.beginBackgroundTask(
            withName: "CodexTurnCompletion"
        ) { [weak self] in
            self?.endBackgroundProcessing()
        }
        #endif
    }

    /// End the extended background execution request.
    func endBackgroundProcessing() {
        #if canImport(UIKit)
        guard self.backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(self.backgroundTaskID)
        self.backgroundTaskID = .invalid
        #endif
    }

    /// End background task if no active turns remain.
    private func endBackgroundProcessingIfIdle() {
        #if canImport(UIKit)
        if self.activeTurnIDByThread.isEmpty {
            self.endBackgroundProcessing()
        }
        #endif
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
        self.turnStreamingPhaseByThread.removeAll()
        self.streamedItemPrefixKeys.removeAll()
        self.availableModels = []
        self.availableCollaborationModes = []
        self.mcpServers = []
        self.availableSkills = []
        self.availableApps = []
        self.availableSlashCommands = []
        self.rateLimits = []
        self.contextUsageByThread.removeAll()
        self.state = .disconnected
        self.connectedEndpoint = ""
        self.endBackgroundProcessing()
    }

    func appendLocalEcho(_ text: String, to threadID: String) {
        let existing = self.transcriptByThread[threadID] ?? ""
        let separator = existing.isEmpty ? "" : "\n"
        self.transcriptByThread[threadID] = existing + "\(separator)User: \(text)\nAssistant: "
    }

    func clearThreadTranscript(_ threadID: String) {
        self.transcriptByThread.removeValue(forKey: threadID)
    }

    func activeTurnID(for threadID: String?) -> String? {
        guard let threadID else { return nil }
        return self.activeTurnIDByThread[threadID]
    }

    func turnStreamingPhase(for threadID: String?) -> TurnStreamingPhase? {
        guard let threadID else { return nil }
        return self.turnStreamingPhaseByThread[threadID]
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

    func refreshRateLimits() async throws -> [AppServerRateLimitSummary] {
        guard self.state == .connected else {
            throw AppServerClientError.notConnected
        }

        do {
            let result = try await self.request(method: "account/rateLimits/read", params: nil)
            var parsed = Self.parseRateLimitCatalog(result)
            if parsed.isEmpty, let object = result.objectValue, let data = object["data"] {
                parsed = Self.parseRateLimitCatalog(data)
            }
            self.rateLimits = parsed
            return parsed
        } catch let AppServerClientError.remote(code, message) where code == -32601 {
            self.rateLimits = []
            self.appendEvent("account/rateLimits/read unavailable: \(message)")
            return []
        }
    }

    func contextUsage(for threadID: String?) -> AppServerContextUsageSummary? {
        guard let threadID else { return nil }
        return self.contextUsageByThread[threadID]
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
                cwd: thread.cwd,
                model: Self.nonEmpty(thread.model),
                reasoningEffort: Self.normalizedReasoningEffort(thread.reasoningEffort)
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
        let detail = self.convertThread(
            payload.thread,
            modelOverride: payload.model,
            reasoningEffortOverride: payload.reasoningEffort
        )
        self.transcriptByThread[threadID] = Self.renderThread(detail)
        return detail
    }

    func threadStart(cwd: String, approvalPolicy: CodexApprovalPolicy, model: String?) async throws -> String {
        let trimmedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedModel = (trimmedModel?.isEmpty == false) ? trimmedModel : nil

        func requestThreadStart(model: String?) async throws -> String {
            var params: [String: JSONValue] = [
                "cwd": .string(cwd),
                "approvalPolicy": .string(approvalPolicy.rawValue),
            ]
            if let model {
                params["model"] = .string(model)
            }

            let result = try await self.request(method: "thread/start", params: .object(params))
            let payload: ThreadLifecycleResponsePayload = try self.decode(result, as: ThreadLifecycleResponsePayload.self)
            return payload.thread.id
        }

        do {
            return try await requestThreadStart(model: normalizedModel)
        } catch {
            guard normalizedModel != nil,
                  Self.shouldRetryWithoutModel(error) else {
                throw error
            }
            self.appendEvent("thread/start rejected model; retrying without model.")
            return try await requestThreadStart(model: nil)
        }
    }

    func threadFork(threadID: String) async throws -> String {
        let params: JSONValue = .object([
            "threadId": .string(threadID),
        ])
        let result = try await self.request(method: "thread/fork", params: params)
        guard let object = result.objectValue,
              let forkedThreadID = Self.findString(
                in: object,
                paths: [
                    ["thread", "id"],
                    ["threadId"],
                    ["id"],
                ]
              )
        else {
            throw AppServerClientError.malformedResponse
        }
        return forkedThreadID
    }

    enum ReviewDelivery: String {
        case inline
        case detached
    }

    enum ReviewTarget: Equatable {
        case uncommittedChanges
        case baseBranch(String)
        case commit(sha: String, title: String?)
        case custom(String)

        fileprivate var jsonValue: JSONValue {
            switch self {
            case .uncommittedChanges:
                return .object([
                    "type": .string("uncommittedChanges")
                ])
            case .baseBranch(let baseBranch):
                return .object([
                    "type": .string("baseBranch"),
                    "baseBranch": .string(baseBranch)
                ])
            case .commit(let sha, let title):
                var payload: [String: JSONValue] = [
                    "type": .string("commit"),
                    "sha": .string(sha)
                ]
                if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                    payload["title"] = .string(title)
                }
                return .object(payload)
            case .custom(let instructions):
                return .object([
                    "type": .string("custom"),
                    "instructions": .string(instructions)
                ])
            }
        }
    }

    @discardableResult
    func reviewStart(
        threadID: String,
        delivery: ReviewDelivery = .inline,
        target: ReviewTarget = .uncommittedChanges
    ) async throws -> String {
        let targetCandidates: [JSONValue]
        switch target {
        case .baseBranch(let baseBranch):
            targetCandidates = [
                target.jsonValue,
                .object([
                    "type": .string("baseBranch"),
                    "branch": .string(baseBranch)
                ]),
                .object([
                    "type": .string("baseBranch"),
                    "branchName": .string(baseBranch)
                ])
            ]
        default:
            targetCandidates = [target.jsonValue]
        }

        var result: JSONValue?
        for (index, targetCandidate) in targetCandidates.enumerated() {
            do {
                let params: JSONValue = .object([
                    "threadId": .string(threadID),
                    "delivery": .string(delivery.rawValue),
                    "target": targetCandidate
                ])
                result = try await self.request(method: "review/start", params: params)
                break
            } catch {
                let shouldRetry = index < targetCandidates.count - 1
                    && Self.shouldRetryReviewStartTarget(error)
                if shouldRetry {
                    continue
                }
                throw error
            }
        }

        guard let result else {
            throw AppServerClientError.malformedResponse
        }
        guard let object = result.objectValue else {
            throw AppServerClientError.malformedResponse
        }

        let reviewThreadID = Self.findString(
            in: object,
            paths: [
                ["reviewThreadId"],
                ["threadId"],
                ["thread", "id"],
            ]
        ) ?? threadID

        if let turnID = Self.findString(in: object, paths: [["turn", "id"]]) {
            self.activeTurnIDByThread[reviewThreadID] = turnID
            self.turnStreamingPhaseByThread[reviewThreadID] = .thinking
        }
        return reviewThreadID
    }

    func threadResume(threadID: String) async throws -> CodexThreadDetail {
        let params: JSONValue = .object(["threadId": .string(threadID)])
        let result = try await self.request(method: "thread/resume", params: params)
        let payload: ThreadResumeResponsePayload = try self.decode(result, as: ThreadResumeResponsePayload.self)
        let detail = self.convertThread(
            payload.thread,
            modelOverride: payload.model,
            reasoningEffortOverride: payload.reasoningEffort
        )
        self.transcriptByThread[threadID] = Self.renderThread(detail)
        return detail
    }

    func threadArchive(threadID: String, archived: Bool) async throws {
        let params: JSONValue = .object([
            "threadId": .string(threadID),
        ])
        let method = archived ? "thread/archive" : "thread/unarchive"
        _ = try await self.request(method: method, params: params)
    }

    @discardableResult
    func turnStart(
        threadID: String,
        inputText: String,
        model: String?,
        effort: String?,
        collaborationModeID: String? = nil
    ) async throws -> String {
        let trimmedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedModel = (trimmedModel?.isEmpty == false) ? trimmedModel : nil
        let trimmedEffort = effort?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEffort = (trimmedEffort?.isEmpty == false) ? trimmedEffort : nil
        let normalizedCollaborationModeID = Self.nonEmpty(collaborationModeID)

        func requestTurnStart(
            model: String?,
            effort: String?,
            collaborationModeID: String?
        ) async throws -> String {
            var params: [String: JSONValue] = [
                "threadId": .string(threadID),
                "input": .array([
                    .object([
                        "type": .string("text"),
                        "text": .string(inputText),
                    ])
                ]),
            ]

            if let model {
                params["model"] = .string(model)
            }
            if let effort {
                params["effort"] = .string(effort)
            }
            if let collaborationModeID,
               let collaborationMode = Self.collaborationModePayload(for: collaborationModeID) {
                params["collaborationMode"] = collaborationMode
            }

            let result = try await self.request(method: "turn/start", params: .object(params))
            let payload: TurnStartResponsePayload = try self.decode(result, as: TurnStartResponsePayload.self)
            self.activeTurnIDByThread[threadID] = payload.turn.id
            self.turnStreamingPhaseByThread[threadID] = .thinking
            return payload.turn.id
        }

        func requestTurnStartWithFallbacks(
            model: String?,
            effort: String?,
            collaborationModeID: String?
        ) async throws -> String {
            do {
                return try await requestTurnStart(
                    model: model,
                    effort: effort,
                    collaborationModeID: collaborationModeID
                )
            } catch {
                if effort != nil,
                   Self.shouldRetryWithoutEffort(error) {
                    self.appendEvent("turn/start rejected effort; retrying without effort.")
                    return try await requestTurnStartWithFallbacks(
                        model: model,
                        effort: nil,
                        collaborationModeID: collaborationModeID
                    )
                }

                if model != nil,
                   Self.shouldRetryWithoutModel(error) {
                    self.appendEvent("turn/start rejected model; retrying without model.")
                    return try await requestTurnStartWithFallbacks(
                        model: nil,
                        effort: effort,
                        collaborationModeID: collaborationModeID
                    )
                }

                if collaborationModeID != nil,
                   Self.shouldRetryWithoutCollaborationMode(error) {
                    self.appendEvent("turn/start rejected collaboration mode; retrying without collaboration mode.")
                    return try await requestTurnStartWithFallbacks(
                        model: model,
                        effort: effort,
                        collaborationModeID: nil
                    )
                }

                throw error
            }
        }

        return try await requestTurnStartWithFallbacks(
            model: normalizedModel,
            effort: normalizedEffort,
            collaborationModeID: normalizedCollaborationModeID
        )
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
        self.turnStreamingPhaseByThread[threadID] = .thinking
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
        self.turnStreamingPhaseByThread.removeValue(forKey: threadID)
        self.endBackgroundProcessingIfIdle()
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
        self.availableModels = []
        self.availableCollaborationModes = []
        self.mcpServers = []
        self.availableSkills = []
        self.availableApps = []
        self.availableSlashCommands = []
        self.turnStreamingPhaseByThread.removeAll()
        self.streamedItemPrefixKeys.removeAll()
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
            Task { @MainActor [weak self] in
                await self?.refreshCatalogs(primaryCWD: nil)
            }
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
        var attempt = 0
        while true {
            do {
                return try await self.requestOnce(method: method, params: params)
            } catch let AppServerClientError.remote(code, message) where code == -32001 {
                guard attempt < self.overloadRetryMaxAttempts - 1 else {
                    throw AppServerClientError.remote(code: code, message: message)
                }

                let baseDelaySeconds = pow(2.0, Double(attempt)) * 0.25
                let jitterSeconds = Double.random(in: 0...(baseDelaySeconds * 0.25))
                let delaySeconds = baseDelaySeconds + jitterSeconds
                self.appendEvent("Server overloaded; retrying \(method) in \(String(format: "%.2f", delaySeconds))s")

                try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
                attempt += 1
                continue
            } catch {
                throw error
            }
        }
    }

    private func requestOnce(method: String, params: JSONValue?) async throws -> JSONValue {
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
            self.turnStreamingPhaseByThread[threadID] = .responding

        case "item/plan/delta":
            guard let threadID = paramsObject["threadId"]?.stringValue else {
                return
            }
            let itemID = Self.findString(
                in: paramsObject,
                paths: [
                    ["itemId"],
                    ["item", "id"],
                ]
            )
            let delta = Self.findRawString(
                in: paramsObject,
                paths: [
                    ["delta"],
                    ["textDelta"],
                ]
            ) ?? ""
            self.appendStreamedItemDelta(
                threadID: threadID,
                itemID: itemID,
                kind: "plan",
                prefix: "Plan: ",
                delta: delta
            )
            if self.turnStreamingPhaseByThread[threadID] == nil {
                self.turnStreamingPhaseByThread[threadID] = .thinking
            }

        case "item/reasoning/summaryTextDelta":
            guard let threadID = paramsObject["threadId"]?.stringValue else {
                return
            }
            let itemID = Self.findString(
                in: paramsObject,
                paths: [
                    ["itemId"],
                    ["item", "id"],
                ]
            )
            let summaryIndex = Self.findInt(
                in: paramsObject,
                paths: [
                    ["summaryIndex"],
                    ["summary", "index"],
                ]
            ) ?? 0
            let delta = Self.findRawString(
                in: paramsObject,
                paths: [
                    ["delta"],
                    ["textDelta"],
                    ["summaryTextDelta"],
                ]
            ) ?? ""
            self.appendStreamedItemDelta(
                threadID: threadID,
                itemID: itemID,
                kind: "reasoning-\(summaryIndex)",
                prefix: "Reasoning: ",
                delta: delta
            )
            if self.turnStreamingPhaseByThread[threadID] == nil {
                self.turnStreamingPhaseByThread[threadID] = .thinking
            }

        case "item/started":
            guard let threadID = paramsObject["threadId"]?.stringValue else {
                return
            }
            let itemObject = paramsObject["item"]?.objectValue ?? paramsObject
            let itemType = Self.findString(
                in: itemObject,
                paths: [
                    ["type"],
                    ["itemType"],
                    ["item_type"],
                ]
            )?.lowercased() ?? ""
            if itemType.contains("agentmessage") || itemType.contains("agent_message") {
                self.turnStreamingPhaseByThread[threadID] = .responding
            } else if self.turnStreamingPhaseByThread[threadID] == nil {
                self.turnStreamingPhaseByThread[threadID] = .thinking
            }

        case "turn/started":
            if let threadID = paramsObject["threadId"]?.stringValue,
               let turn = paramsObject["turn"]?.objectValue,
               let turnID = turn["id"]?.stringValue {
                self.activeTurnIDByThread[threadID] = turnID
                if self.turnStreamingPhaseByThread[threadID] != .responding {
                    self.turnStreamingPhaseByThread[threadID] = .thinking
                }
                self.transcriptSnapshotBeforeTurn[threadID] = self.transcriptByThread[threadID] ?? ""
                self.appendEvent("Turn started for \(threadID)")
            }

        case "turn/completed", "turn/failed", "turn/cancelled":
            guard let threadID = paramsObject["threadId"]?.stringValue else {
                return
            }
            let turn = paramsObject["turn"]?.objectValue ?? [:]
            let status = turn["status"]?.stringValue
                ?? method.split(separator: "/").last.map(String.init)
                ?? "completed"
            self.appendEvent("Turn \(status) for \(threadID)")

            let fullTranscript = self.transcriptByThread[threadID] ?? ""
            let before = self.transcriptSnapshotBeforeTurn.removeValue(forKey: threadID) ?? ""
            let responseDelta = String(fullTranscript.dropFirst(before.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let snippet = responseDelta.count > 200
                ? String(responseDelta.prefix(200)) + "…"
                : responseDelta
            self.onTurnCompleted?(threadID, status, snippet)

            self.activeTurnIDByThread.removeValue(forKey: threadID)
            self.turnStreamingPhaseByThread.removeValue(forKey: threadID)
            self.clearStreamedItemPrefixKeys(for: threadID)
            self.endBackgroundProcessingIfIdle()

            let normalizedStatus = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let shouldRefreshThreadSnapshot = method == "turn/completed" || normalizedStatus == "completed"
            if shouldRefreshThreadSnapshot, self.state == .connected {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    do {
                        _ = try await self.threadRead(threadID: threadID)
                    } catch {
                        self.appendEvent("thread/read after \(method) failed: \(error.localizedDescription)")
                    }
                }
            }

        case "thread/tokenUsage/updated":
            guard let threadID = paramsObject["threadId"]?.stringValue else {
                return
            }
            let usageObject = paramsObject["tokenUsage"]?.objectValue ?? paramsObject
            let usedTokens = Self.findInt(
                in: usageObject,
                paths: [
                    ["inputTokens"],
                    ["usedTokens"],
                    ["usedInputTokens"],
                    ["usage", "used"],
                ]
            )
            let maxTokens = Self.findInt(
                in: usageObject,
                paths: [
                    ["maxInputTokens"],
                    ["contextWindow", "maxTokens"],
                    ["limit"],
                    ["maxTokens"],
                    ["usage", "limit"],
                ]
            )
            let remainingTokens = Self.findInt(
                in: usageObject,
                paths: [
                    ["remainingInputTokens"],
                    ["contextWindow", "remainingTokens"],
                    ["remainingTokens"],
                    ["remaining"],
                    ["usage", "remaining"],
                ]
            )

            self.contextUsageByThread[threadID] = AppServerContextUsageSummary(
                usedTokens: usedTokens,
                maxTokens: maxTokens,
                remainingTokens: remainingTokens,
                updatedAt: Date()
            )

        case "account/rateLimits/updated":
            var parsed = Self.parseRateLimitCatalog(.object(paramsObject))
            if parsed.isEmpty, let data = paramsObject["data"] {
                parsed = Self.parseRateLimitCatalog(data)
            }
            self.rateLimits = parsed

        case "thread/started":
            if let thread = paramsObject["thread"]?.objectValue,
               let threadID = thread["id"]?.stringValue {
                self.appendEvent("Thread started: \(threadID)")
            }

        case "app/list/updated":
            let rows = paramsObject["data"]?.arrayValue
                ?? paramsObject["apps"]?.arrayValue
                ?? []
            let parsed = Self.parseAppCatalog(rows)
            self.availableApps = parsed.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            self.rebuildSlashCommandCatalog()

        case "error":
            if let message = paramsObject["message"]?.stringValue {
                self.lastErrorMessage = "[Protocol] \(message)"
            }

        default:
            self.appendEvent("Notification: \(method)")
        }
    }

    private func appendStreamedItemDelta(
        threadID: String,
        itemID: String?,
        kind: String,
        prefix: String,
        delta: String
    ) {
        guard !delta.isEmpty else { return }

        let normalizedItemID = Self.nonEmpty(itemID) ?? "unknown"
        let streamKey = "\(threadID)|\(kind)|\(normalizedItemID)"
        var existing = self.transcriptByThread[threadID] ?? ""

        if self.streamedItemPrefixKeys.contains(streamKey) == false {
            if !existing.isEmpty, existing.hasSuffix("\n") == false {
                existing.append("\n")
            }
            existing.append(prefix)
            self.streamedItemPrefixKeys.insert(streamKey)
        }

        existing.append(delta)
        self.transcriptByThread[threadID] = existing
    }

    private func clearStreamedItemPrefixKeys(for threadID: String) {
        self.streamedItemPrefixKeys = self.streamedItemPrefixKeys.filter { key in
            key.hasPrefix("\(threadID)|") == false
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

        case "tool/requestUserInput", "item/tool/requestUserInput":
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
        self.turnStreamingPhaseByThread.removeAll()
        self.streamedItemPrefixKeys.removeAll()
        self.teardownConnection(closeCode: .abnormalClosure)
        self.endBackgroundProcessing()

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
        self.streamedItemPrefixKeys.removeAll()

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

    func refreshCatalogs(primaryCWD: String?) async {
        guard self.state == .connected else {
            self.availableSlashCommands = []
            return
        }

        async let modelTask: Void = self.refreshModelCatalog()
        async let collaborationModeTask: Void = self.refreshCollaborationModeCatalog()
        async let mcpTask: Void = self.refreshMCPServerCatalog()
        async let skillTask: Void = self.refreshSkillCatalog(primaryCWD: primaryCWD)
        async let appTask: Void = self.refreshAppCatalog()
        _ = await (modelTask, collaborationModeTask, mcpTask, skillTask, appTask)

        self.rebuildSlashCommandCatalog()
    }

    private func refreshModelCatalog() async {
        var entries: [ModelListEntryPayload] = []
        var cursor: String?
        var seenCursors: Set<String> = []

        do {
            while true {
                var params: [String: JSONValue] = [
                    "limit": .number(100),
                    "includeHidden": .bool(false),
                ]
                if let cursor {
                    params["cursor"] = .string(cursor)
                }

                let result = try await self.request(method: "model/list", params: .object(params))
                let payload: ModelListResponsePayload = try self.decode(result, as: ModelListResponsePayload.self)
                entries.append(contentsOf: payload.data)

                guard let nextCursor = Self.nonEmpty(payload.nextCursor),
                      !seenCursors.contains(nextCursor),
                      entries.count < 300
                else {
                    break
                }
                seenCursors.insert(nextCursor)
                cursor = nextCursor
            }
        } catch {
            self.appendEvent("model/list unavailable: \(error.localizedDescription)")
            return
        }

        let catalog = Self.parseModelCatalog(entries)
        guard !catalog.isEmpty else { return }

        self.availableModels = catalog
        if self.nonEmptyOrNil(self.diagnostics.currentModel) == nil,
           let preferredModel = catalog.first(where: { $0.isDefault })?.model ?? catalog.first?.model {
            self.diagnostics.currentModel = preferredModel
        }
        self.rebuildSlashCommandCatalog()
    }

    private func refreshCollaborationModeCatalog() async {
        do {
            let result = try await self.request(method: "collaborationMode/list", params: nil)
            self.availableCollaborationModes = Self.parseCollaborationModeCatalog(result)
        } catch let AppServerClientError.remote(code, message) where code == -32601 {
            self.availableCollaborationModes = []
            self.appendEvent("collaborationMode/list unavailable: \(message)")
        } catch {
            self.availableCollaborationModes = []
            self.appendEvent("collaborationMode/list unavailable: \(error.localizedDescription)")
        }

        self.rebuildSlashCommandCatalog()
    }

    private func refreshMCPServerCatalog() async {
        var rows: [JSONValue] = []
        var cursor: String?
        var seenCursors: Set<String> = []

        do {
            while true {
                var params: [String: JSONValue] = [
                    "limit": .number(100)
                ]
                if let cursor {
                    params["cursor"] = .string(cursor)
                }

                let result = try await self.request(method: "mcpServerStatus/list", params: .object(params))
                let pageRows = Self.dataArray(from: result, fallbackKeys: ["servers", "mcpServers"])
                rows.append(contentsOf: pageRows)

                guard let nextCursor = Self.nextCursor(from: result),
                      !nextCursor.isEmpty,
                      !seenCursors.contains(nextCursor),
                      rows.count < 300
                else {
                    break
                }

                seenCursors.insert(nextCursor)
                cursor = nextCursor
            }
        } catch {
            self.appendEvent("mcpServerStatus/list unavailable: \(error.localizedDescription)")
            self.mcpServers = []
            self.rebuildSlashCommandCatalog()
            return
        }

        let parsed = Self.parseMCPServerCatalog(rows)
        self.mcpServers = parsed.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        self.rebuildSlashCommandCatalog()
    }

    private func refreshSkillCatalog(primaryCWD: String?) async {
        var params: [String: JSONValue] = [
            "forceReload": .bool(false)
        ]
        if let primaryCWD = Self.nonEmpty(primaryCWD) {
            params["cwds"] = .array([.string(primaryCWD)])
        }

        do {
            let result = try await self.request(method: "skills/list", params: .object(params))
            var entries = Self.dataArray(from: result)
            if entries.isEmpty,
               let object = result.objectValue,
               let directSkills = object["skills"]?.arrayValue {
                entries = [.object(["skills": .array(directSkills)])]
            }
            let parsed = Self.parseSkillCatalog(entries)
            self.availableSkills = parsed.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        } catch {
            self.appendEvent("skills/list unavailable: \(error.localizedDescription)")
            self.availableSkills = []
        }

        self.rebuildSlashCommandCatalog()
    }

    private func refreshAppCatalog() async {
        var rows: [JSONValue] = []
        var cursor: String?
        var seenCursors: Set<String> = []

        do {
            while true {
                var params: [String: JSONValue] = [
                    "limit": .number(100),
                    "forceRefetch": .bool(false),
                ]
                if let cursor {
                    params["cursor"] = .string(cursor)
                }

                let result = try await self.request(method: "app/list", params: .object(params))
                let pageRows = Self.dataArray(from: result, fallbackKeys: ["apps"])
                rows.append(contentsOf: pageRows)

                guard let nextCursor = Self.nextCursor(from: result),
                      !nextCursor.isEmpty,
                      !seenCursors.contains(nextCursor),
                      rows.count < 300
                else {
                    break
                }

                seenCursors.insert(nextCursor)
                cursor = nextCursor
            }
        } catch {
            self.appendEvent("app/list unavailable: \(error.localizedDescription)")
            self.availableApps = []
            self.rebuildSlashCommandCatalog()
            return
        }

        let parsed = Self.parseAppCatalog(rows)
        self.availableApps = parsed.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        self.rebuildSlashCommandCatalog()
    }

    private func rebuildSlashCommandCatalog() {
        guard self.state == .connected else {
            self.availableSlashCommands = []
            return
        }

        self.availableSlashCommands = [
            AppServerSlashCommandDescriptor(
                kind: .newThread,
                command: "/new",
                title: "New thread",
                description: "Start a new conversation.",
                systemImage: "plus.bubble",
                requiresThread: false
            ),
            AppServerSlashCommandDescriptor(
                kind: .forkThread,
                command: "/fork",
                title: "Fork",
                description: "Fork the current thread.",
                systemImage: "arrow.triangle.branch",
                requiresThread: true
            ),
            AppServerSlashCommandDescriptor(
                kind: .startReview,
                command: "/review",
                title: "Code review",
                description: "Run reviewer on current changes.",
                systemImage: "checkmark.shield",
                requiresThread: true
            ),
            AppServerSlashCommandDescriptor(
                kind: .startPlanMode,
                command: "/plan",
                title: "Plan mode",
                description: "Switch next turns to planning mode.",
                systemImage: "checklist",
                requiresThread: false
            ),
            AppServerSlashCommandDescriptor(
                kind: .showStatus,
                command: "/status",
                title: "Status",
                description: "Show connection, model, and catalog status.",
                systemImage: "info.circle",
                requiresThread: false
            ),
        ]
    }

    private static func parseModelCatalog(_ entries: [ModelListEntryPayload]) -> [AppServerModelDescriptor] {
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

    private static func parseCollaborationModeCatalog(_ result: JSONValue) -> [AppServerCollaborationModeDescriptor] {
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

    private static func parseMCPServerCatalog(_ rows: [JSONValue]) -> [AppServerMCPServerSummary] {
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

    private static func parseSkillCatalog(_ entries: [JSONValue]) -> [AppServerSkillSummary] {
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

    private static func parseAppCatalog(_ rows: [JSONValue]) -> [AppServerAppSummary] {
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

    private static func parseRateLimitCatalog(_ result: JSONValue) -> [AppServerRateLimitSummary] {
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

    private static func parseRateLimitSummaries(
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

    private static func parseSingleRateLimitSummary(
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

    private static func findDate(in object: [String: JSONValue], paths: [[String]]) -> Date? {
        for path in paths {
            guard let value = Self.value(at: path, in: object),
                  let parsed = Self.parseRateLimitDate(value) else {
                continue
            }
            return parsed
        }
        return nil
    }

    private static func parseRateLimitDate(_ raw: JSONValue) -> Date? {
        switch raw {
        case .number(let seconds):
            return Date(timeIntervalSince1970: seconds)
        case .string(let value):
            return Self.parseRateLimitDate(value)
        default:
            return nil
        }
    }

    private static func parseRateLimitDate(_ raw: String) -> Date? {
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

    private static func dataArray(from result: JSONValue, fallbackKeys: [String] = []) -> [JSONValue] {
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

    private static func nextCursor(from result: JSONValue) -> String? {
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

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedReasoningEffort(_ raw: String?) -> String? {
        guard let raw = Self.nonEmpty(raw) else { return nil }
        return raw.lowercased()
    }

    private static func collaborationModePayload(for rawModeID: String) -> JSONValue? {
        guard let modeID = Self.nonEmpty(rawModeID) else {
            return nil
        }
        return .object([
            "id": .string(modeID)
        ])
    }

    private static func shouldRetryWithoutEffort(_ error: Error) -> Bool {
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

    private static func shouldRetryWithoutModel(_ error: Error) -> Bool {
        guard case let AppServerClientError.remote(code, message) = error else {
            return false
        }
        let normalized = message.lowercased()
        return code == -32602
            || normalized.contains("invalid params")
            || normalized.contains("model")
            || normalized.contains("unknown field")
    }

    private static func shouldRetryWithoutCollaborationMode(_ error: Error) -> Bool {
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

    private static func shouldRetryReviewStartTarget(_ error: Error) -> Bool {
        guard case let AppServerClientError.remote(code, message) = error else {
            return false
        }
        let normalized = message.lowercased()
        return code == -32602
            || normalized.contains("invalid params")
            || normalized.contains("unknown field")
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

    private static func findRawString(in object: [String: JSONValue], paths: [[String]]) -> String? {
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

    private static func findInt(in object: [String: JSONValue], paths: [[String]]) -> Int? {
        for path in paths {
            if let value = Self.value(at: path, in: object)?.intValue {
                return value
            }
        }
        return nil
    }

    private static func findDouble(in object: [String: JSONValue], paths: [[String]]) -> Double? {
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

    private static func findBool(in object: [String: JSONValue], paths: [[String]]) -> Bool? {
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

    private static let iso8601WithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601Basic: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

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

        return "[Connection] WebSocket handshake failed before app-server initialization. codex app-server may reject iOS WebSocket extension negotiation (Sec-WebSocket-Extensions). Run scripts/ws_strip_extensions_proxy.js on the remote host and connect iOS to that proxy URL, or use Terminal tab."
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

    private func convertThread(
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

private struct ModelListResponsePayload: Decodable {
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

private struct ModelListEntryPayload: Decodable {
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
        if let options = try container.decodeIfPresent([ModelReasoningEffortPayload].self, forKey: key) {
            return options
        }
        if let values = try container.decodeIfPresent([String].self, forKey: key) {
            return values.map { ModelReasoningEffortPayload(effort: $0, description: nil) }
        }
        return nil
    }
}

private struct ModelReasoningEffortPayload: Decodable {
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

private struct ThreadListEntryPayload: Decodable {
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
        self.cwd = try container.decode(String.self, forKey: .cwd)
        self.model = try container.decodeIfPresent(String.self, forKey: .model)
        self.reasoningEffort = try container.decodeIfPresent(String.self, forKey: .reasoningEffort)
            ?? container.decodeIfPresent(String.self, forKey: .reasoningEffortSnake)
            ?? container.decodeIfPresent(String.self, forKey: .effort)
    }
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

private struct ThreadResumeResponsePayload: Decodable {
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

private struct ThreadReadThreadPayload: Decodable {
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

private struct ThreadReadTurnPayload: Decodable {
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
