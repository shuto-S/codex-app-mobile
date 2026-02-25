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
    var hasReceivedMessageOnCurrentConnection = false
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


    private func appendEvent(_ message: String) {
        self.eventLog.append(message)
        if self.eventLog.count > 200 {
            self.eventLog.removeFirst(self.eventLog.count - 200)
        }
    }
}


