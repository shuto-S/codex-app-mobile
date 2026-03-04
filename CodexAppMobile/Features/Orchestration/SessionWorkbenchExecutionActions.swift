import Foundation
import SwiftUI
import Textual

extension SessionWorkbenchView {
    static func normalizedRemotePathForThreadScope(_ rawPath: String) -> String {
        var normalized = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return ""
        }

        while normalized.contains("//") {
            normalized = normalized.replacingOccurrences(of: "//", with: "/")
        }

        if normalized == "/" {
            return normalized
        }

        while normalized.count > 1 && normalized.hasSuffix("/") {
            normalized.removeLast()
        }

        return normalized
    }

    static func isThreadPath(_ threadPath: String, inWorkspacePath workspacePath: String) -> Bool {
        let normalizedThreadPath = Self.normalizedRemotePathForThreadScope(threadPath)
        let normalizedWorkspacePath = Self.normalizedRemotePathForThreadScope(workspacePath)

        guard !normalizedThreadPath.isEmpty,
              !normalizedWorkspacePath.isEmpty else {
            return false
        }

        return normalizedThreadPath == normalizedWorkspacePath
    }

    static func normalizedThreadIDForPendingScope(_ rawThreadID: String?) -> String {
        rawThreadID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static func isPendingRequest(
        _ request: AppServerPendingRequest,
        scopedToThreadID threadID: String?
    ) -> Bool {
        let normalizedScopeThreadID = Self.normalizedThreadIDForPendingScope(threadID)
        guard !normalizedScopeThreadID.isEmpty else { return false }

        let normalizedRequestThreadID = Self.normalizedThreadIDForPendingScope(request.threadID)
        guard !normalizedRequestThreadID.isEmpty else { return false }

        return normalizedRequestThreadID == normalizedScopeThreadID
    }

    static func pendingUserInputScopeKey(threadID: String, requestIDKey: String) -> String? {
        let normalizedThreadID = Self.normalizedThreadIDForPendingScope(threadID)
        let normalizedRequestIDKey = requestIDKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedThreadID.isEmpty, !normalizedRequestIDKey.isEmpty else {
            return nil
        }
        return "\(normalizedThreadID)|\(normalizedRequestIDKey)"
    }

    func scheduleSessionRefresh(_ work: Set<RefreshWork>, debounceNanoseconds: UInt64 = 0) {
        guard !work.isEmpty else { return }
        self.pendingRefreshWork.formUnion(work)
        self.refreshCoordinatorTask?.cancel()

        self.refreshCoordinatorTask = Task { @MainActor in
            if debounceNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: debounceNanoseconds)
            }
            guard !Task.isCancelled else { return }

            let workToRun = self.pendingRefreshWork
            self.pendingRefreshWork.removeAll()

            if workToRun.contains(.threads) {
                self.refreshThreads()
            }
            if workToRun.contains(.catalogs) {
                self.refreshAppServerCatalogsForCurrentWorkspace()
            }
            if workToRun.contains(.selectedThreadDetail),
               let threadID = self.selectedThreadID {
                self.loadThread(threadID)
            }

            self.refreshCoordinatorTask = nil
        }
    }

    func refreshThreads(debounceNanoseconds: UInt64 = 0) {
        guard let selectedWorkspace else {
            self.presentCriticalErrorDialog("Select a project first.")
            return
        }

        self.refreshThreadsTask?.cancel()
        self.isRefreshingThreads = true

        let workspaceSnapshot = selectedWorkspace
        self.refreshThreadsTask = Task { @MainActor in
            defer {
                if !Task.isCancelled {
                    self.isRefreshingThreads = false
                }
            }

            if debounceNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: debounceNanoseconds)
            }
            guard !Task.isCancelled else { return }

            if self.isSSHTransport {
                let localThreads = self.appState.threadBookmarkStore
                    .threads(for: workspaceSnapshot.id)
                    .filter { !$0.archived }
                if let selectedThreadID,
                   localThreads.contains(where: { $0.threadID == selectedThreadID }) {
                    // Keep current selection.
                } else if self.selectedThreadID != nil {
                    self.selectedThreadID = nil
                    self.appState.hostSessionStore.selectThread(hostID: self.host.id, threadID: nil)
                }
                return
            }

            do {
                if self.appState.appServerClient.state != .connected {
                    try await self.appState.appServerClient.connect(to: self.host)
                }
                guard !Task.isCancelled else { return }

                let fetched = try await self.appState.appServerClient.threadList(archived: false, limit: 300)
                guard !Task.isCancelled else { return }
                let scoped = fetched.filter {
                    Self.isThreadPath($0.cwd, inWorkspacePath: workspaceSnapshot.remotePath)
                }
                let existingByThreadID = Dictionary(
                    uniqueKeysWithValues: self.appState.threadBookmarkStore
                        .threads(for: workspaceSnapshot.id)
                        .map { ($0.threadID, $0) }
                )
                let summaries: [CodexThreadSummary] = scoped.map { thread in
                    let existing = existingByThreadID[thread.id]
                    return CodexThreadSummary(
                        threadID: thread.id,
                        hostID: self.host.id,
                        workspaceID: workspaceSnapshot.id,
                        preview: thread.preview,
                        updatedAt: thread.updatedAt,
                        archived: thread.archived,
                        ephemeral: thread.ephemeral,
                        cwd: thread.cwd,
                        model: thread.model ?? existing?.model,
                        reasoningEffort: thread.reasoningEffort ?? existing?.reasoningEffort
                    )
                }

                self.appState.threadBookmarkStore.replaceThreads(
                    for: workspaceSnapshot.id,
                    hostID: self.host.id,
                    with: summaries
                )

                let selectedWorkspaceThreads = self.threads(for: workspaceSnapshot.id)
                if let selectedThreadID = self.selectedThreadID,
                   selectedWorkspaceThreads.contains(where: { $0.threadID == selectedThreadID }) {
                    self.loadThread(selectedThreadID)
                } else if self.selectedThreadID != nil {
                    self.selectedThreadID = nil
                    self.appState.hostSessionStore.selectThread(hostID: self.host.id, threadID: nil)
                }
            } catch is CancellationError {
                return
            } catch {
                if !Task.isCancelled {
                    self.presentCriticalErrorDialog(self.appState.appServerClient.userFacingMessage(for: error))
                }
            }
        }
    }

    func sendPrompt(forceNewThread: Bool) {
        let originalPrompt = self.prompt
        let originalTokenBadges = self.selectedComposerTokenBadges
        let trimmedPrompt = self.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return }
        let promptForRequest = self.composePromptForRequest(from: trimmedPrompt)
        guard let selectedWorkspace else {
            self.presentCriticalErrorDialog("Select a project first.")
            return
        }

        self.scrollToBottomRequestCount += 1

        if self.isSSHTransport {
            self.sendPromptViaSSH(
                promptForRequest: promptForRequest,
                displayPrompt: trimmedPrompt,
                selectedWorkspace: selectedWorkspace,
                forceNewThread: forceNewThread
            )
            return
        }

        let collaborationModeIDForRequest = self.composerCollaborationModeIDForRequest
        let didRequestPlanMode = self.isPlanCollaborationMode(collaborationModeIDForRequest)

        self.prompt = ""
        self.selectedComposerTokenBadges = []
        self.pendingPromptDispatchCount += 1

        Task {
            defer {
                self.pendingPromptDispatchCount = max(0, self.pendingPromptDispatchCount - 1)
            }
            do {
                if self.appState.appServerClient.state != .connected {
                    try await self.appState.appServerClient.connect(to: self.host)
                }

                var threadID = forceNewThread ? nil : self.selectedThreadID
                if threadID == nil {
                    threadID = try await self.appState.appServerClient.threadStart(
                        cwd: selectedWorkspace.remotePath,
                        approvalPolicy: selectedWorkspace.defaultApprovalPolicy,
                        model: self.composerModelForRequest
                    )
                }

                guard let threadID else {
                    self.presentCriticalErrorDialog("Failed to resolve thread.")
                    return
                }

                self.selectedThreadID = threadID
                self.appState.hostSessionStore.selectThread(hostID: self.host.id, threadID: threadID)

                var selectedModelForThread = self.selectedThreadSummary?.model
                var selectedReasoningForThread = self.selectedThreadSummary?.reasoningEffort
                let selectedEphemeralForThread = self.selectedThreadSummary?.ephemeral ?? false
                if let activeTurnID = self.appState.appServerClient.activeTurnID(for: threadID) {
                    try await self.appState.appServerClient.turnSteer(
                        threadID: threadID,
                        expectedTurnID: activeTurnID,
                        inputText: promptForRequest
                    )
                    if didRequestPlanMode {
                        self.showComposerInfo(
                            "Plan mode will apply to the next new turn after the active turn completes.",
                            tone: .status,
                            autoDismissAfter: 4.0
                        )
                    }
                } else {
                    let turnStartResult = try await self.appState.appServerClient.turnStart(
                        threadID: threadID,
                        inputText: promptForRequest,
                        model: self.composerModelForRequest,
                        effort: self.selectedComposerReasoning,
                        collaborationModeID: collaborationModeIDForRequest
                    )
                    if didRequestPlanMode {
                        if turnStartResult.collaborationModeApplied {
                            self.armPlanUserInputAutoPresentation(
                                threadID: threadID,
                                turnID: turnStartResult.turnID
                            )
                        } else {
                            self.showComposerInfo(
                                "Plan mode was not applied by the server. Prompt sent in default mode.",
                                tone: .status,
                                autoDismissAfter: 5.0
                            )
                        }
                        self.consumePlanModeAfterSend()
                    }
                    selectedModelForThread = self.composerModelForRequest
                    selectedReasoningForThread = self.selectedComposerReasoning
                }

                self.dismissPendingUserInputForPrompt(on: threadID)
                self.appState.appServerClient.appendLocalEcho(promptForRequest, to: threadID)

                self.appState.threadBookmarkStore.upsert(
                    summary: CodexThreadSummary(
                        threadID: threadID,
                        hostID: self.host.id,
                        workspaceID: selectedWorkspace.id,
                        preview: trimmedPrompt,
                        updatedAt: Date(),
                        archived: false,
                        ephemeral: selectedEphemeralForThread,
                        cwd: selectedWorkspace.remotePath,
                        model: selectedModelForThread,
                        reasoningEffort: selectedReasoningForThread
                    )
                )
            } catch {
                let message = self.appState.appServerClient.userFacingMessage(for: error)
                self.presentCriticalErrorDialog(message)
                if self.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   self.selectedComposerTokenBadges.isEmpty {
                    self.prompt = originalPrompt
                    self.selectedComposerTokenBadges = originalTokenBadges
                    self.isPromptFieldFocused = true
                }
            }
        }
    }

    func presentCommandPalette() {
        guard self.isCommandPaletteAvailable else { return }
        if self.isCommandPalettePresented {
            self.dismissCommandPalette()
            return
        }
        self.dismissStatusPanel()
        self.dismissMCPStatusSheet()
        self.dismissReviewModePicker()
        self.isCommandPalettePresented = true
        self.refreshCommandPalette()
    }

    func dismissCommandPalette() {
        self.isCommandPalettePresented = false
        self.dismissReviewModePicker()
    }

    func presentReviewModePicker() {
        guard self.isCommandPalettePresented else {
            self.presentCriticalErrorDialog("Open commands and select /review again.")
            return
        }
        self.reviewModeSelection = .uncommittedChanges
        self.reviewBaseBranch = ""
        self.isReviewModePickerPresented = true
    }

    func dismissReviewModePicker() {
        self.isReviewModePickerPresented = false
        self.reviewModeSelection = .uncommittedChanges
        self.reviewBaseBranch = ""
        self.isReviewBaseBranchFieldFocused = false
    }

    func presentPendingUserInputPanel(_ request: AppServerPendingRequest) {
        guard case .userInput = request.kind else {
            return
        }
        guard Self.isPendingRequest(request, scopedToThreadID: self.selectedThreadID) else {
            return
        }
        self.dismissStatusPanel()
        self.dismissMCPStatusSheet()
        self.dismissReviewModePicker()
        self.dismissCommandPalette()
        self.activePendingRequest = request
    }

    func handleSelectedThreadChanged() {
        guard let activeRequest = self.activePendingRequest else {
            return
        }
        if Self.isPendingRequest(activeRequest, scopedToThreadID: self.selectedThreadID) == false {
            self.activePendingRequest = nil
        }
    }

    func handlePendingRequestsUpdated() {
        self.pruneDismissedPendingUserInputScopeKeys()
        let pendingRequests = self.selectedThreadPendingRequests

        if let activeRequest = self.activePendingRequest,
           pendingRequests.contains(where: { $0.id == activeRequest.id }) == false {
            self.activePendingRequest = nil
        }

        if self.shouldPresentNextUserInputPanelAfterPlan,
           let userInputRequest = pendingRequests.first(where: { request in
               self.shouldAutoPresentPlanUserInputRequest(request)
           }) {
            self.clearPlanUserInputAutoPresentation()
            self.presentPendingUserInputPanel(userInputRequest)
        }
    }

    func handleResolvedPendingRequestUpdated() {
        guard let resolved = self.appState.appServerClient.lastResolvedPendingRequest else {
            return
        }

        let matchedSheetRequest = self.activePendingRequest?.requestIDKey == resolved.requestIDKey

        if matchedSheetRequest {
            self.activePendingRequest = nil
        }

        let resolvedThreadID = Self.normalizedThreadIDForPendingScope(resolved.threadID)
        if resolvedThreadID != Self.normalizedThreadIDForPendingScope(self.selectedThreadID) {
            return
        }

        let now = Date()
        if let suppressedThreadID = self.suppressResolvedPendingRequestAlertThreadID {
            if now > self.suppressResolvedPendingRequestAlertExpiresAt {
                self.suppressResolvedPendingRequestAlertThreadID = nil
                self.suppressResolvedPendingRequestAlertExpiresAt = .distantPast
            } else if Self.normalizedThreadIDForPendingScope(suppressedThreadID) == resolvedThreadID {
                self.suppressResolvedPendingRequestAlertThreadID = nil
                self.suppressResolvedPendingRequestAlertExpiresAt = .distantPast
                return
            }
        }

        self.showComposerInfo(
            "Request \(resolved.requestIDKey) for thread \(resolved.threadID) was resolved by the server.",
            tone: .status,
            autoDismissAfter: 4.0
        )
    }

    func presentFirstPendingRequest() {
        if let userInputRequest = self.selectedThreadPendingUserInputRequests.first {
            self.presentPendingUserInputPanel(userInputRequest)
            return
        }

        self.activePendingRequest = self.selectedThreadPendingRequests.first
    }

    func pendingUserInputScopeKey(for request: AppServerPendingRequest) -> String? {
        Self.pendingUserInputScopeKey(threadID: request.threadID, requestIDKey: request.requestIDKey)
    }

    func isPendingUserInputSuppressed(_ request: AppServerPendingRequest) -> Bool {
        guard case .userInput = request.kind,
              let scopeKey = self.pendingUserInputScopeKey(for: request) else {
            return false
        }
        return self.dismissedPendingUserInputScopeKeys.contains(scopeKey)
    }

    func dismissPendingUserInputForPrompt(on threadID: String) {
        let scopeKeys = self.appState.appServerClient.pendingRequests.compactMap { request -> String? in
            guard Self.isPendingRequest(request, scopedToThreadID: threadID),
                  case .userInput = request.kind else {
                return nil
            }
            return self.pendingUserInputScopeKey(for: request)
        }
        guard !scopeKeys.isEmpty else { return }
        self.dismissedPendingUserInputScopeKeys.formUnion(scopeKeys)
    }

    func pruneDismissedPendingUserInputScopeKeys() {
        guard !self.dismissedPendingUserInputScopeKeys.isEmpty else { return }
        let activeScopeKeys = Set(self.appState.appServerClient.pendingRequests.compactMap { request -> String? in
            guard case .userInput = request.kind else {
                return nil
            }
            return self.pendingUserInputScopeKey(for: request)
        })
        self.dismissedPendingUserInputScopeKeys = self.dismissedPendingUserInputScopeKeys
            .intersection(activeScopeKeys)
    }

    func handleCommandPaletteBackAction() {
        if self.isReviewModePickerPresented {
            self.dismissReviewModePicker()
            return
        }
    }

    func refreshCommandPalette() {
        guard !self.isSSHTransport else { return }
        self.isCommandPaletteRefreshing = true

        Task {
            defer {
                self.isCommandPaletteRefreshing = false
            }
            do {
                try await self.ensureAppServerReady(refreshCatalogs: true)
            } catch {
                self.presentCriticalErrorDialog(self.appState.appServerClient.userFacingMessage(for: error))
            }
        }
    }

    func presentStatusPanel() {
        guard !self.isSSHTransport else {
            self.presentCriticalErrorDialog("Slash commands are only available in App Server mode.")
            return
        }
        self.dismissMCPStatusSheet()
        self.dismissCommandPalette()
        self.isStatusPanelPresented = true
        self.statusSnapshot = self.makeStatusSnapshot()
        self.refreshStatusPanel()
    }

    func dismissStatusPanel() {
        self.isStatusPanelPresented = false
    }

    func presentMCPStatusSheet() {
        guard !self.isSSHTransport else {
            self.presentCriticalErrorDialog("Slash commands are only available in App Server mode.")
            return
        }
        self.dismissStatusPanel()
        self.dismissCommandPalette()
        self.isMCPStatusSheetPresented = true
        self.refreshMCPStatusSheet()
    }

    func dismissMCPStatusSheet() {
        self.isMCPStatusSheetPresented = false
    }

    func refreshMCPStatusSheet() {
        guard !self.isSSHTransport else { return }
        self.isMCPStatusRefreshing = true
        self.mcpStatusHeadline = "Refreshing MCP server status..."

        Task {
            defer {
                self.isMCPStatusRefreshing = false
            }
            do {
                try await self.ensureAppServerReady(refreshCatalogs: false)
                self.mcpStatusHeadline = try await self.appState.appServerClient.mcpServerStatusHeadline()
            } catch {
                self.mcpStatusHeadline = self.appState.appServerClient.userFacingMessage(for: error)
            }
        }
    }

    func refreshStatusPanel() {
        guard !self.isSSHTransport else { return }
        self.isStatusRefreshing = true
        self.statusSnapshot = self.makeStatusSnapshot()

        Task {
            defer {
                self.isStatusRefreshing = false
            }
            do {
                try await self.ensureAppServerReady(refreshCatalogs: true)
                _ = try await self.appState.appServerClient.runDiagnostics()
                _ = try await self.appState.appServerClient.refreshRateLimits()
                self.statusSnapshot = self.makeStatusSnapshot()
            } catch {
                self.presentCriticalErrorDialog(self.appState.appServerClient.userFacingMessage(for: error))
            }
        }
    }

    func presentCriticalErrorDialog(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if self.isCriticalErrorDialogPresented,
           self.criticalErrorDialogMessage == trimmed {
            return
        }
        self.criticalErrorDialogMessage = trimmed
        self.isCriticalErrorDialogPresented = true
    }

    func showComposerInfo(
        _ text: String,
        tone: InfoBannerTone = .success,
        autoDismissAfter _: TimeInterval = 0
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let current = self.composerInfoMessage,
           current.text == trimmed,
           current.tone == tone {
            return
        }
        self.composerInfoMessage = ComposerInfoMessage(text: trimmed, tone: tone)
    }

    func clearComposerInfo() {
        self.composerInfoMessage = nil
    }

    func handleCommandPaletteSelection(_ row: CommandPaletteRow) {
        switch row {
        case .command(let command):
            if command.kind != .startReview {
                self.dismissCommandPalette()
            }
            self.executeSlashCommand(command)
        case .skill(let skill):
            self.insertComposerToken("$\(skill.name)")
            self.dismissCommandPalette()
        }
    }

    func insertComposerToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let badge = Self.makeComposerTokenBadge(token: trimmed) else { return }
        let normalized = badge.token.lowercased()
        if !self.selectedComposerTokenBadges.contains(where: { $0.token.lowercased() == normalized }) {
            self.selectedComposerTokenBadges.append(badge)
        }
        self.isPromptFieldFocused = true
    }

    func composePromptForRequest(from trimmedPrompt: String) -> String {
        guard !self.selectedComposerTokenBadges.isEmpty else {
            return trimmedPrompt
        }
        let prefixes = self.selectedComposerTokenBadges.map(\.token)
        return (prefixes + [trimmedPrompt]).joined(separator: "\n")
    }

    static func makeComposerTokenBadge(token: String) -> ComposerTokenBadge? {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        if normalized.hasPrefix("$") {
            let skillName = String(normalized.dropFirst())
            return ComposerTokenBadge(
                id: "skill-\(normalized.lowercased())",
                token: normalized,
                title: skillName.isEmpty ? "Skill" : "Skill \(skillName)"
            )
        }

        return nil
    }

    func executeSlashCommand(_ command: AppServerSlashCommandDescriptor) {
        guard !self.isSSHTransport else {
            self.presentCriticalErrorDialog("Slash commands are only available in App Server mode.")
            return
        }
        guard !self.isSlashCommandDisabled(command) else {
            if command.kind == .forkThread,
               self.selectedThreadSummary?.ephemeral == true {
                self.presentCriticalErrorDialog("Ephemeral threads cannot be forked.")
            } else {
                self.presentCriticalErrorDialog("Select a thread first.")
            }
            return
        }

        switch command.kind {
        case .newThread:
            self.createNewThread()
        case .forkThread:
            self.forkCurrentThread()
        case .startReview:
            self.presentReviewModePicker()
        case .startPlanMode:
            self.startPlanModeSlashCommand()
        case .showStatus:
            self.showStatusSlashCommand()
        case .showMCPStatus:
            self.showMCPStatusSlashCommand()
        }
    }

    func refreshAppServerCatalogsForCurrentWorkspace(debounceNanoseconds: UInt64 = 0) {
        guard !self.isSSHTransport else { return }
        self.refreshCatalogsTask?.cancel()
        let primaryCWD = self.selectedWorkspace?.remotePath
        self.refreshCatalogsTask = Task { @MainActor in
            if debounceNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: debounceNanoseconds)
            }
            guard !Task.isCancelled else { return }
            await self.appState.appServerClient.refreshCatalogs(primaryCWD: primaryCWD)
        }
    }

    func ensureAppServerReady(refreshCatalogs: Bool) async throws {
        if self.appState.appServerClient.state != .connected {
            try await self.appState.appServerClient.connect(to: self.host)
        }
        if refreshCatalogs {
            await self.appState.appServerClient.refreshCatalogs(primaryCWD: self.selectedWorkspace?.remotePath)
        }
    }

    func forkCurrentThread() {
        guard let sourceThreadID = self.selectedThreadID else {
            self.presentCriticalErrorDialog("Select a thread first.")
            return
        }
        let sourceSummary = self.selectedThreadSummary
        if sourceSummary?.ephemeral == true {
            self.presentCriticalErrorDialog("Ephemeral threads cannot be forked.")
            return
        }
        let selectedWorkspace = self.selectedWorkspace

        Task {
            do {
                try await self.ensureAppServerReady(refreshCatalogs: false)
                let forkedThreadID = try await self.appState.appServerClient.threadFork(threadID: sourceThreadID)

                self.selectedThreadID = forkedThreadID
                self.appState.hostSessionStore.selectThread(hostID: self.host.id, threadID: forkedThreadID)
                if let selectedWorkspace {
                    self.appState.threadBookmarkStore.upsert(
                        summary: CodexThreadSummary(
                            threadID: forkedThreadID,
                            hostID: self.host.id,
                            workspaceID: selectedWorkspace.id,
                            preview: sourceSummary?.preview ?? "Forked from \(sourceThreadID)",
                            updatedAt: Date(),
                            archived: false,
                            cwd: selectedWorkspace.remotePath,
                            model: sourceSummary?.model,
                            reasoningEffort: sourceSummary?.reasoningEffort
                        )
                    )
                }

                self.loadThread(forkedThreadID)
                self.scheduleSessionRefresh([.threads])
                self.showComposerInfo("Forked thread: \(forkedThreadID)")
            } catch {
                self.presentCriticalErrorDialog(self.appState.appServerClient.userFacingMessage(for: error))
            }
        }
    }

    func startReviewAgainstBaseBranch() {
        let trimmedBaseBranch = self.reviewBaseBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBaseBranch.isEmpty else {
            self.presentCriticalErrorDialog("Enter a base branch name.")
            return
        }
        self.dismissCommandPalette()
        self.startReviewForCurrentThread(
            target: .baseBranch(trimmedBaseBranch),
            preview: "Code review (\(trimmedBaseBranch))",
            successMessage: "Started review against \(trimmedBaseBranch) in a new thread."
        )
    }

    func startReviewForCurrentThread(
        target: AppServerClient.ReviewTarget,
        preview: String = "Code review",
        successMessage: String = "Started code review in a new thread."
    ) {
        guard let sourceThreadID = self.selectedThreadID else {
            self.presentCriticalErrorDialog("Select a thread first.")
            return
        }
        let sourceSummary = self.selectedThreadSummary
        let selectedWorkspace = self.selectedWorkspace

        Task {
            do {
                try await self.ensureAppServerReady(refreshCatalogs: false)
                let reviewThreadID = try await self.appState.appServerClient.reviewStart(
                    threadID: sourceThreadID,
                    delivery: .detached,
                    target: target
                )
                self.selectedThreadID = reviewThreadID
                self.appState.hostSessionStore.selectThread(hostID: self.host.id, threadID: reviewThreadID)

                if let selectedWorkspace,
                   self.appState.threadBookmarkStore
                    .threads(for: selectedWorkspace.id)
                    .contains(where: { $0.threadID == reviewThreadID }) == false {
                    self.appState.threadBookmarkStore.upsert(
                        summary: CodexThreadSummary(
                            threadID: reviewThreadID,
                            hostID: self.host.id,
                            workspaceID: selectedWorkspace.id,
                            preview: preview,
                            updatedAt: Date(),
                            archived: false,
                            cwd: selectedWorkspace.remotePath,
                            model: sourceSummary?.model,
                            reasoningEffort: sourceSummary?.reasoningEffort
                        )
                    )
                }

                self.loadThread(reviewThreadID)
                self.scheduleSessionRefresh([.threads])
                self.showComposerInfo(successMessage)
            } catch {
                self.presentCriticalErrorDialog(self.appState.appServerClient.userFacingMessage(for: error))
            }
        }
    }

    func showStatusSlashCommand() {
        self.presentStatusPanel()
    }

    func showMCPStatusSlashCommand() {
        self.presentMCPStatusSheet()
    }

    func startPlanModeSlashCommand() {
        let catalog = self.appState.appServerClient.availableCollaborationModes
        let planModeDiscovered = catalog.contains(where: { mode in
            mode.normalizedID == "plan" || mode.title.lowercased().contains("plan")
        })
        self.composerCollaborationModeID = self.planCollaborationModeID
        self.clearPlanUserInputAutoPresentation()
        if planModeDiscovered {
            self.showComposerInfo("Plan mode enabled. Send a prompt to continue.", tone: .status)
        } else if catalog.isEmpty {
            self.showComposerInfo(
                "Plan mode enabled. Server capability is unknown; we will try on send.",
                tone: .status,
                autoDismissAfter: 4.0
            )
        } else {
            self.showComposerInfo(
                "Plan mode enabled. This server may not support it; we will retry without it if rejected.",
                tone: .status,
                autoDismissAfter: 4.0
            )
        }
        self.isPromptFieldFocused = true
    }

    func disablePlanMode() {
        let wasEnabled = self.composerCollaborationModeIDForRequest != nil
        self.composerCollaborationModeID = ""
        self.clearPlanUserInputAutoPresentation()
        if wasEnabled {
            self.showComposerInfo("Plan mode disabled.", tone: .status)
        }
    }

    func consumePlanModeAfterSend() {
        guard self.isPlanModeEnabled else { return }
        self.composerCollaborationModeID = ""
    }

    func armPlanUserInputAutoPresentation(threadID: String, turnID: String) {
        self.shouldPresentNextUserInputPanelAfterPlan = true
        self.pendingPlanUserInputThreadID = threadID
        self.pendingPlanUserInputTurnID = turnID
    }

    func clearPlanUserInputAutoPresentation() {
        self.shouldPresentNextUserInputPanelAfterPlan = false
        self.pendingPlanUserInputThreadID = nil
        self.pendingPlanUserInputTurnID = nil
    }

    func shouldAutoPresentPlanUserInputRequest(_ request: AppServerPendingRequest) -> Bool {
        guard case .userInput = request.kind else { return false }

        let expectedThreadID = self.pendingPlanUserInputThreadID?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let expectedTurnID = self.pendingPlanUserInputTurnID?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let requestThreadID = request.threadID.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestTurnID = request.turnID.trimmingCharacters(in: .whitespacesAndNewlines)

        if !expectedThreadID.isEmpty,
           !requestThreadID.isEmpty,
           requestThreadID != expectedThreadID {
            return false
        }
        if !expectedTurnID.isEmpty,
           !requestTurnID.isEmpty,
           requestTurnID != expectedTurnID {
            return false
        }
        return true
    }

    func sendPromptViaSSH(
        promptForRequest: String,
        displayPrompt: String,
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
                    prompt: promptForRequest,
                    resumeThreadID: resumeThreadID,
                    forceNewThread: forceNewThread,
                    model: self.composerModelForRequest
                )

                self.selectedThreadID = result.threadID
                self.appState.hostSessionStore.selectThread(hostID: self.host.id, threadID: result.threadID)
                self.appendSSHTranscript(prompt: promptForRequest, response: result.assistantText, threadID: result.threadID)

                self.appState.threadBookmarkStore.upsert(
                    summary: CodexThreadSummary(
                        threadID: result.threadID,
                        hostID: self.host.id,
                        workspaceID: selectedWorkspace.id,
                        preview: displayPrompt,
                        updatedAt: Date(),
                        archived: false,
                        cwd: selectedWorkspace.remotePath
                    )
                )

                self.prompt = ""
                self.selectedComposerTokenBadges = []
                self.showComposerInfo("Executed via codex exec over SSH.", tone: .status)
            } catch {
                let message = self.userFacingSSHError(error)
                self.presentCriticalErrorDialog(message)
                self.isPromptFieldFocused = true
            }
        }
    }

    func appendSSHTranscript(prompt: String, response: String, threadID: String) {
        var existing = self.sshTranscriptByThread[threadID] ?? ""
        if !existing.isEmpty {
            existing += "\n"
        }
        existing += "User: \(prompt)\nAssistant: \(response)"
        self.sshTranscriptByThread[threadID] = existing
    }

    func userFacingSSHError(_ error: Error) -> String {
        if let codexError = error as? SSHCodexExecError,
           let description = codexError.errorDescription,
           !description.isEmpty {
            return "[SSH] \(description)"
        }
        let endpoint = HostKeyStore.endpointKey(host: self.host.host, port: self.host.sshPort)
        return SSHConnectionErrorFormatter.message(for: error, endpoint: endpoint)
    }

    func loadThread(_ threadID: String) {
        if self.isSSHTransport {
            return
        }
        Task {
            do {
                let detail: CodexThreadDetail
                do {
                    detail = try await self.appState.appServerClient.threadResume(threadID: threadID)
                } catch {
                    detail = try await self.appState.appServerClient.threadRead(threadID: threadID)
                }

                let latestTurnModel = detail.turns.compactMap(\.model).last
                let latestTurnReasoning = detail.turns.compactMap(\.reasoningEffort).last
                let selectedSummary = self.selectedThreadSummary
                let resolvedModel = detail.model ?? latestTurnModel ?? selectedSummary?.model
                let resolvedReasoning = detail.reasoningEffort ?? latestTurnReasoning ?? selectedSummary?.reasoningEffort

                self.applyComposerSelection(model: resolvedModel, reasoningEffort: resolvedReasoning)
                self.updateThreadBookmarkSettings(
                    threadID: threadID,
                    ephemeral: detail.ephemeral,
                    model: resolvedModel,
                    reasoningEffort: resolvedReasoning
                )
            } catch {
                self.presentCriticalErrorDialog(self.appState.appServerClient.userFacingMessage(for: error))
            }
        }
    }

    func interruptActiveTurn() {
        if self.isSSHTransport {
            return
        }

        guard let threadID = self.selectedThreadID,
              let turnID = self.appState.appServerClient.activeTurnID(for: threadID) else {
            return
        }

        self.suppressResolvedPendingRequestAlertThreadID = threadID
        self.suppressResolvedPendingRequestAlertExpiresAt = Date().addingTimeInterval(5.0)

        Task {
            do {
                try await self.appState.appServerClient.turnInterrupt(threadID: threadID, turnID: turnID)
                self.showComposerInfo("Canceled.", tone: .status)
                self.scrollToBottomRequestCount += 1
            } catch {
                self.suppressResolvedPendingRequestAlertThreadID = nil
                self.suppressResolvedPendingRequestAlertExpiresAt = .distantPast
                self.presentCriticalErrorDialog(self.appState.appServerClient.userFacingMessage(for: error))
            }
        }
    }

    func archiveThread(summary: CodexThreadSummary, archived: Bool) {
        if summary.ephemeral {
            self.presentCriticalErrorDialog("Ephemeral threads cannot be archived.")
            return
        }
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
                self.scheduleSessionRefresh([.threads])
            } catch {
                self.presentCriticalErrorDialog(self.appState.appServerClient.userFacingMessage(for: error))
            }
        }
    }

    func openInTerminal() {
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
