import Foundation
import SwiftUI
import Textual

struct SessionWorkbenchView: View {
    private enum AssistantStreamingPhase {
        case thinking
        case responding
    }

    private enum ReviewModeSelection: String, Equatable {
        case uncommittedChanges
        case baseBranch
    }

    private enum InfoBannerTone {
        case status
        case success
        case error
    }

    private struct ComposerInfoMessage: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let tone: InfoBannerTone
    }

    private struct StatusLimitBarSnapshot: Equatable, Identifiable {
        let id: String
        let label: String
        let remainingPercent: Double?
        let resetAt: Date?
    }

    private struct StatusPanelSnapshot: Equatable {
        let sessionID: String
        let contextUsedTokens: Int?
        let contextMaxTokens: Int?
        let contextRemainingPercent: Double?
        let limits: [StatusLimitBarSnapshot]
        let fallbackStatus: String
        let updatedAt: Date
    }

    private struct ComposerTokenBadge: Identifiable, Equatable {
        enum Kind: Equatable {
            case mcp
            case skill
        }

        let id: String
        let kind: Kind
        let token: String
        let title: String
    }

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    let host: RemoteHost

    @State private var selectedWorkspaceID: UUID?
    @State private var selectedThreadID: String?
    @State private var prompt = ""
    @State private var localErrorMessage = ""
    @State private var localStatusMessage = ""
    @State private var isRefreshingThreads = false
    @State private var isRunningSSHAction = false
    @State private var isPresentingProjectEditor = false
    @State private var editingWorkspace: ProjectWorkspace?
    @State private var workspacePendingDeletion: ProjectWorkspace?
    @State private var activePendingRequest: AppServerPendingRequest?
    @State private var sshTranscriptByThread: [String: String] = [:]
    @State private var isMenuOpen = false
    @State private var selectedComposerModel = ""
    @State private var selectedComposerReasoning = "low"
    @State private var isCommandPalettePresented = false
    @State private var isCommandPaletteRefreshing = false
    @State private var isReviewModePickerPresented = false
    @State private var reviewModeSelection: ReviewModeSelection = .uncommittedChanges
    @State private var reviewBaseBranch = ""
    @State private var composerCollaborationModeID = ""
    @State private var pendingUserInputRequest: AppServerPendingRequest?
    @State private var pendingUserInputAnswers: [String: String] = [:]
    @State private var pendingUserInputSubmitError = ""
    @State private var isSubmittingPendingUserInput = false
    @State private var shouldPresentNextUserInputPanelAfterPlan = false
    @State private var isStatusPanelPresented = false
    @State private var isStatusRefreshing = false
    @State private var statusSnapshot: StatusPanelSnapshot?
    @State private var composerInfoMessage: ComposerInfoMessage?
    @State private var composerInfoDismissTask: Task<Void, Never>?
    @State private var selectedComposerTokenBadges: [ComposerTokenBadge] = []
    @State private var pendingPromptDispatchCount = 0
    @State private var chatDistanceFromBottom: CGFloat = 0
    @State private var scrollToBottomRequestCount = 0
    @FocusState private var isPromptFieldFocused: Bool
    @FocusState private var isReviewBaseBranchFieldFocused: Bool

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

    private var selectedWorkspaceThreads: [CodexThreadSummary] {
        guard let selectedWorkspaceID else { return [] }
        return self.threads(for: selectedWorkspaceID)
    }

    private func threads(for workspaceID: UUID) -> [CodexThreadSummary] {
        self.appState.threadBookmarkStore
            .threads(for: workspaceID)
            .filter { !$0.archived }
    }

    private var selectedThreadSummary: CodexThreadSummary? {
        guard let selectedWorkspaceID,
              let selectedThreadID else {
            return nil
        }
        return self.threads(for: selectedWorkspaceID).first(where: { $0.threadID == selectedThreadID })
    }

    private var selectedThreadTitle: String {
        guard let summary = self.selectedThreadSummary else {
            return "New Thread"
        }
        let title = summary.preview.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "New Thread" : title
    }

    private var selectedWorkspaceTitle: String {
        self.selectedWorkspace?.displayName ?? "Project"
    }

    private var selectedThreadTranscript: String {
        guard let selectedThreadID else { return "" }
        if self.isSSHTransport {
            return self.sshTranscriptByThread[selectedThreadID] ?? ""
        }
        return self.appState.appServerClient.transcriptByThread[selectedThreadID] ?? ""
    }

    private var parsedChatMessages: [SessionChatMessage] {
        Self.parseChatMessages(from: self.selectedThreadTranscript)
    }

    private var isPromptEmpty: Bool {
        self.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var composerTokenBadges: [ComposerTokenBadge] {
        self.selectedComposerTokenBadges
    }

    private var canSendPrompt: Bool {
        !self.isPromptEmpty
            && !self.isRunningSSHAction
            && self.selectedWorkspace != nil
    }

    private var hasVisibleAssistantReplyForLatestPrompt: Bool {
        let lastUserIndex = self.parsedChatMessages.lastIndex(where: { $0.role == .user })
        let lastAssistantIndex = self.parsedChatMessages.lastIndex { message in
            guard message.role == .assistant else { return false }
            return !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        guard let lastAssistantIndex else {
            return false
        }
        guard let lastUserIndex else {
            return true
        }
        return lastAssistantIndex > lastUserIndex
    }

    private var assistantStreamingPhase: AssistantStreamingPhase? {
        if self.isAwaitingPromptDispatch {
            return .thinking
        }

        if self.hasVisibleAssistantReplyForLatestPrompt {
            return nil
        }

        if self.isSSHTransport {
            return self.isRunningSSHAction ? .responding : nil
        }

        guard let selectedThreadID else { return nil }

        if let phase = self.appState.appServerClient.turnStreamingPhase(for: selectedThreadID) {
            switch phase {
            case .thinking:
                return .thinking
            case .responding:
                return .responding
            }
        }

        return self.appState.appServerClient.activeTurnID(for: selectedThreadID) != nil
            ? .thinking
            : nil
    }

    private func assistantStreamingBaseText(for phase: AssistantStreamingPhase) -> String {
        switch phase {
        case .thinking:
            return "Thinking"
        case .responding:
            return "Generating reply"
        }
    }

    private func animatedStreamingStatus(baseText: String, date: Date) -> String {
        let step = Int(date.timeIntervalSinceReferenceDate * 2).quotientAndRemainder(dividingBy: 4).remainder
        let dots = String(repeating: ".", count: max(1, step))
        return baseText + dots
    }

    private var shouldShowScrollToBottomButton: Bool {
        self.selectedThreadID != nil && self.chatDistanceFromBottom > 220
    }

    private var shouldAutoFollowChatUpdates: Bool {
        self.selectedThreadID != nil && self.chatDistanceFromBottom <= 64
    }

    private var isComposerInteractive: Bool {
        !self.isRunningSSHAction && self.selectedWorkspace != nil
    }

    private var fallbackReasoningEffortOptions: [CodexReasoningEffortOption] {
        [
            CodexReasoningEffortOption(value: "low", description: nil),
            CodexReasoningEffortOption(value: "medium", description: nil),
            CodexReasoningEffortOption(value: "high", description: nil),
        ]
    }

    private var composerModelDescriptors: [AppServerModelDescriptor] {
        var options: [AppServerModelDescriptor] = []
        var seenModels: Set<String> = []

        if !self.isSSHTransport {
            for model in self.appState.appServerClient.availableModels {
                let trimmed = model.model.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !seenModels.contains(trimmed) else { continue }
                seenModels.insert(trimmed)
                options.append(model)
            }
        }

        func appendIfNeeded(_ rawModel: String, displayName: String? = nil, isDefault: Bool = false) {
            let trimmed = rawModel.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seenModels.contains(trimmed) else { return }
            seenModels.insert(trimmed)
            options.append(
                AppServerModelDescriptor(
                    model: trimmed,
                    displayName: displayName ?? trimmed,
                    reasoningEffortOptions: [],
                    defaultReasoningEffort: nil,
                    isDefault: isDefault
                )
            )
        }

        appendIfNeeded(self.selectedComposerModel)
        appendIfNeeded(self.selectedWorkspace?.defaultModel ?? "", isDefault: true)
        appendIfNeeded(self.appState.appServerClient.diagnostics.currentModel, isDefault: true)
        appendIfNeeded("gpt-5.3-codex", displayName: "GPT-5.3-Codex")
        appendIfNeeded("gpt-5.2-codex", displayName: "GPT-5.2-Codex")

        return options
    }

    private var composerModelForRequest: String? {
        let selected = self.selectedComposerModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !selected.isEmpty {
            return selected
        }

        let workspaceDefault = self.selectedWorkspace?.defaultModel.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !workspaceDefault.isEmpty {
            return workspaceDefault
        }

        if let defaultModel = self.composerModelDescriptors.first(where: { $0.isDefault })?.model {
            return defaultModel
        }

        let currentModel = self.appState.appServerClient.diagnostics.currentModel
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return currentModel.isEmpty ? nil : currentModel
    }

    private var selectedComposerModelDescriptor: AppServerModelDescriptor? {
        guard let selectedModel = self.composerModelForRequest else { return nil }
        return self.composerModelDescriptors.first(where: { $0.model == selectedModel })
    }

    private var composerModelDisplayName: String {
        if let selectedComposerModelDescriptor {
            return selectedComposerModelDescriptor.displayName
        }

        if let defaultModel = self.composerModelDescriptors.first(where: { $0.isDefault }) {
            return defaultModel.displayName
        }

        return "GPT-5.3-Codex"
    }

    private var composerReasoningOptions: [CodexReasoningEffortOption] {
        if let selectedComposerModelDescriptor,
           !selectedComposerModelDescriptor.reasoningEffortOptions.isEmpty {
            return selectedComposerModelDescriptor.reasoningEffortOptions
        }
        return self.fallbackReasoningEffortOptions
    }

    private var composerReasoningDisplayName: String {
        let selected = self.selectedComposerReasoning.trimmingCharacters(in: .whitespacesAndNewlines)
        if let matched = self.composerReasoningOptions.first(where: { $0.value == selected }) {
            return matched.displayName
        }
        if !selected.isEmpty {
            return CodexReasoningEffortOption(value: selected, description: nil).displayName
        }
        return self.fallbackReasoningEffortOptions.first?.displayName ?? "Low"
    }

    private var slashCommandDescriptors: [AppServerSlashCommandDescriptor] {
        guard !self.isSSHTransport else { return [] }
        return self.appState.appServerClient.availableSlashCommands
    }

    private var commandPaletteRows: [CommandPaletteRow] {
        buildCommandPaletteRows(
            commands: self.slashCommandDescriptors,
            mcpServers: self.appState.appServerClient.mcpServers,
            skills: self.appState.appServerClient.availableSkills
        )
    }

    private var composerCollaborationModeIDForRequest: String? {
        let trimmed = self.composerCollaborationModeID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var planCollaborationModeID: String {
        if let mode = self.appState.appServerClient.availableCollaborationModes.first(where: {
            $0.normalizedID == "plan" || $0.title.lowercased().contains("plan")
        }) {
            return mode.id
        }
        return "plan"
    }

    private var isPlanModeEnabled: Bool {
        guard let modeID = self.composerCollaborationModeIDForRequest else {
            return false
        }
        let normalizedModeID = modeID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedPlanID = self.planCollaborationModeID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalizedModeID == "plan" || normalizedModeID == normalizedPlanID
    }

    private var isAwaitingPromptDispatch: Bool {
        self.pendingPromptDispatchCount > 0
    }

    private func isPlanCollaborationMode(_ modeID: String?) -> Bool {
        guard let modeID else { return false }
        let normalizedModeID = modeID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedModeID.isEmpty else { return false }
        let normalizedPlanID = self.planCollaborationModeID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalizedModeID == "plan" || normalizedModeID == normalizedPlanID
    }

    private var isCommandPaletteSubpanelPresented: Bool {
        self.isReviewModePickerPresented || self.pendingUserInputRequest != nil
    }

    private var pendingUserInputQuestions: [AppServerUserInputQuestion] {
        guard let request = self.pendingUserInputRequest,
              case .userInput(let questions) = request.kind else {
            return []
        }
        return questions
    }

    private var isCommandPaletteAvailable: Bool {
        !self.isSSHTransport && self.isComposerInteractive
    }

    private var commandPalettePanelMaxHeight: CGFloat {
        #if canImport(UIKit)
        let screenHeight = UIScreen.main.bounds.height
        return min(620, max(440, screenHeight * 0.72))
        #else
        return 500
        #endif
    }

    private var commandPalettePanelMinHeight: CGFloat {
        min(380, self.commandPalettePanelMaxHeight * 0.75)
    }

    private func makeStatusSnapshot() -> StatusPanelSnapshot {
        let contextUsage = self.appState.appServerClient.contextUsage(for: self.selectedThreadID)
        let limits = self.preferredStatusRateLimits(from: self.appState.appServerClient.rateLimits).map {
            StatusLimitBarSnapshot(
                id: $0.id,
                label: self.statusLimitLabel(for: $0),
                remainingPercent: $0.remainingPercent,
                resetAt: $0.resetsAt
            )
        }

        return StatusPanelSnapshot(
            sessionID: self.selectedThreadID ?? "-",
            contextUsedTokens: contextUsage?.usedTokens,
            contextMaxTokens: contextUsage?.maxTokens,
            contextRemainingPercent: contextUsage?.remainingPercent,
            limits: limits,
            fallbackStatus: self.appState.appServerClient.state.rawValue,
            updatedAt: Date()
        )
    }

    private func preferredStatusRateLimits(from limits: [AppServerRateLimitSummary]) -> [AppServerRateLimitSummary] {
        guard !limits.isEmpty else { return [] }
        let prioritized = limits.sorted { lhs, rhs in
            let lhsRank = self.statusRateLimitRank(lhs)
            let rhsRank = self.statusRateLimitRank(rhs)
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            if let lhsWindow = lhs.windowMinutes, let rhsWindow = rhs.windowMinutes, lhsWindow != rhsWindow {
                return lhsWindow < rhsWindow
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        var unique: [AppServerRateLimitSummary] = []
        var seenKeys: Set<String> = []
        for limit in prioritized {
            let key = "\(limit.name.lowercased())-\(limit.windowMinutes ?? -1)"
            guard seenKeys.insert(key).inserted else { continue }
            unique.append(limit)
            if unique.count >= 2 { break }
        }
        return unique
    }

    private func statusRateLimitRank(_ limit: AppServerRateLimitSummary) -> Int {
        if let window = limit.windowMinutes {
            if window == 300 { return 0 }
            if window == 10080 { return 1 }
        }
        let name = limit.name.lowercased()
        if name.contains("5h") { return 0 }
        if name.contains("7d") { return 1 }
        return 2
    }

    private func statusLimitLabel(for limit: AppServerRateLimitSummary) -> String {
        if let window = limit.windowMinutes {
            if window == 300 { return "5h limit" }
            if window == 10080 { return "7d limit" }
        }
        return "\(limit.name) limit"
    }

    private func isSlashCommandDisabled(_ command: AppServerSlashCommandDescriptor) -> Bool {
        command.requiresThread && self.selectedThreadID == nil
    }

    private var menuWidth: CGFloat {
        304
    }

    private var isDarkMode: Bool {
        self.colorScheme == .dark
    }

    private var windowSafeAreaTopInset: CGFloat {
        #if canImport(UIKit)
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let keyWindow = scenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        return keyWindow?.safeAreaInsets.top ?? 0
        #else
        return 0
        #endif
    }

    private func glassWhiteTint(light: Double, dark: Double) -> Color {
        Color.white.opacity(self.isDarkMode ? dark : light)
    }

    private func accentGlassTint(light: Double, dark: Double) -> Color {
        Color.accentColor.opacity(self.isDarkMode ? dark : light)
    }

    private var glassStrokeColor: Color {
        self.glassWhiteTint(light: 0.30, dark: 0.20)
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
                Color.black.opacity(self.isDarkMode ? 0.34 : 0.18)
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

        }
        .safeAreaInset(edge: .top, spacing: 0) {
            self.chatHeaderArea
        }
        .overlay(alignment: .leading) {
            self.sideMenu
                .zIndex(2)
        }
        .overlay(alignment: .leading) {
            if !self.isMenuOpen {
                self.menuEdgeOpenHandle
                    .zIndex(3)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.88), value: self.isMenuOpen)
        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: self.isCommandPalettePresented)
        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: self.isStatusPanelPresented)
        .animation(.easeOut(duration: 0.18), value: self.composerInfoMessage?.id)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            self.appState.selectHost(self.host.id)
            self.appState.hostSessionStore.markOpened(hostID: self.host.id)
            self.restoreSelectionFromSession()
            if self.selectedWorkspaceID == nil,
               let firstWorkspace = self.workspaces.first {
                self.selectedWorkspaceID = firstWorkspace.id
                self.appState.hostSessionStore.selectProject(hostID: self.host.id, projectID: firstWorkspace.id)
            }
            if self.isSSHTransport {
                self.appState.appServerClient.disconnect()
            }
            self.syncComposerControlsWithWorkspace()
            if self.selectedWorkspace != nil {
                self.refreshThreads()
                self.refreshAppServerCatalogsForCurrentWorkspace()
            }
        }
        .onChange(of: self.selectedWorkspaceID) {
            self.syncComposerControlsWithWorkspace()
            if self.selectedWorkspace != nil {
                self.refreshThreads()
                self.refreshAppServerCatalogsForCurrentWorkspace()
            }
        }
        .onChange(of: self.selectedComposerModel) {
            self.syncComposerReasoningWithModel()
        }
        .onChange(of: self.scenePhase) {
            if self.scenePhase == .active, self.selectedWorkspace != nil {
                self.refreshThreads()
                if let threadID = self.selectedThreadID {
                    self.loadThread(threadID)
                }
            }
        }
        .onChange(of: self.appState.appServerClient.availableModels) {
            self.syncComposerControlsWithWorkspace()
        }
        .onChange(of: self.appState.appServerClient.pendingRequests) {
            self.handlePendingRequestsUpdated()
        }
        .alert(
            "Delete this project?",
            isPresented: Binding(
                get: { self.workspacePendingDeletion != nil },
                set: { isPresented in
                    if isPresented == false {
                        self.workspacePendingDeletion = nil
                    }
                }
            ),
            presenting: self.workspacePendingDeletion
        ) { workspace in
            Button("Cancel", role: .cancel) {
                self.workspacePendingDeletion = nil
            }
            Button("Delete", role: .destructive) {
                self.deleteWorkspace(workspace)
            }
        } message: { workspace in
            Text("Delete \"\(workspace.displayName)\"? This cannot be undone.")
        }
        .sheet(isPresented: self.$isPresentingProjectEditor) {
            ProjectEditorView(
                workspace: self.editingWorkspace,
                host: self.host,
                hostPassword: self.appState.remoteHostStore.password(for: self.host.id)
            ) { draft in
                let isCreatingWorkspace = self.editingWorkspace == nil
                let savedWorkspaceID = self.appState.projectStore.upsert(
                    workspaceID: self.editingWorkspace?.id,
                    hostID: self.host.id,
                    draft: draft
                )
                if isCreatingWorkspace {
                    self.selectedWorkspaceID = savedWorkspaceID
                    self.createNewThread()
                } else {
                    self.restoreSelectionFromSession()
                }
            }
        }
        .sheet(item: self.$activePendingRequest) { request in
            PendingRequestSheet(request: request)
                .environmentObject(self.appState)
        }
        .onDisappear {
            self.clearComposerInfo()
        }
    }

    private var chatBackground: some View {
        Color.black
    }

    private var chatHeader: some View {
        HStack(spacing: 12) {
            Button {
                self.isPromptFieldFocused = false
                self.isCommandPalettePresented = false
                self.isStatusPanelPresented = false
                withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                    self.isMenuOpen.toggle()
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.white)

            VStack(alignment: .leading, spacing: 0) {
                Text(self.selectedThreadTitle)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                Text(self.selectedWorkspaceTitle)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.62))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                if let selectedThreadSummary {
                    Button(role: .destructive) {
                        self.archiveThread(summary: selectedThreadSummary, archived: true)
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                } else {
                    Text("No thread to archive")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.white)
            .disabled(self.selectedThreadSummary == nil)
            .opacity(self.selectedThreadSummary == nil ? 0.42 : 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color.black)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.14))
                .frame(height: 0.5)
        }
    }

    private var chatHeaderArea: some View {
        VStack(spacing: 0) {
            self.chatHeader

            if let composerInfoMessage {
                self.chatInfoBanner(text: composerInfoMessage.text, tone: composerInfoMessage.tone)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .background(Color.black)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.black)
    }

    private var chatTimeline: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 14) {
                    if !self.localErrorMessage.isEmpty {
                        self.chatInfoBanner(text: self.localErrorMessage, tone: .error)
                    }

                    if !self.localStatusMessage.isEmpty {
                        self.chatInfoBanner(text: self.localStatusMessage, tone: .status)
                    }

                    if !self.isSSHTransport,
                       !self.appState.appServerClient.pendingRequests.isEmpty {
                        Button {
                            self.presentFirstPendingRequest()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "clock.badge.exclamationmark")
                                Text("\(self.appState.appServerClient.pendingRequests.count) approvals pending")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                            }
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    if self.selectedWorkspace == nil {
                        self.chatPlaceholder("Create or select a project.")
                    } else if self.selectedThreadID != nil && self.parsedChatMessages.isEmpty {
                        self.chatPlaceholder("No messages yet.")
                    } else if self.selectedThreadID != nil {
                        ForEach(self.parsedChatMessages) { message in
                            self.chatMessageRow(message)
                        }
                    }

                    if let assistantStreamingPhase {
                        self.chatStreamingStatusRow(baseText: self.assistantStreamingBaseText(for: assistantStreamingPhase))
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("chat-bottom")
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 18)
            }
            .background(Color.black)
            .scrollDismissesKeyboard(.interactively)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                self.distanceToChatBottom(from: geometry)
            } action: { _, newValue in
                self.chatDistanceFromBottom = newValue
            }
            .overlay(alignment: .bottom) {
                if self.shouldShowScrollToBottomButton {
                    self.scrollToBottomButton(proxy: proxy)
                        .padding(.bottom, 12)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .animation(.easeOut(duration: 0.18), value: self.shouldShowScrollToBottomButton)
            .onAppear {
                self.scrollToBottom(proxy: proxy)
            }
            .onChange(of: self.scrollToBottomRequestCount) {
                self.scrollToBottom(proxy: proxy)
            }
            .onChange(of: self.selectedThreadID) {
                self.scrollToBottom(proxy: proxy)
            }
            .onChange(of: self.selectedThreadTranscript) {
                guard self.shouldAutoFollowChatUpdates else { return }
                self.scrollToBottom(proxy: proxy)
            }
            .onChange(of: self.assistantStreamingPhase) {
                guard self.shouldAutoFollowChatUpdates else { return }
                self.scrollToBottom(proxy: proxy)
            }
        }
    }

    @ViewBuilder
    private func scrollToBottomButton(proxy: ScrollViewProxy) -> some View {
        Button {
            self.scrollToBottom(proxy: proxy)
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.78))
                .frame(width: 68, height: 40)
                .background {
                    self.glassCardBackground(
                        cornerRadius: 20,
                        tint: self.glassWhiteTint(light: 0.12, dark: 0.08)
                    )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(self.glassStrokeColor.opacity(0.38), lineWidth: 0.8)
                }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func composerPickerChip(_ title: String, minWidth: CGFloat? = nil) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(Color.white.opacity(0.92))
            .padding(.horizontal, 12)
            .frame(minWidth: minWidth, minHeight: 44, maxHeight: 44)
        .background {
            self.glassCardBackground(cornerRadius: 22, tint: self.glassWhiteTint(light: 0.20, dark: 0.14))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(self.glassStrokeColor.opacity(0.56), lineWidth: 0.9)
        }
    }

    @ViewBuilder
    private var composerKeyboardDismissButton: some View {
        Button {
            self.isPromptFieldFocused = false
        } label: {
            Image(systemName: "keyboard.chevron.compact.down")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))
                .frame(width: 44, height: 44)
                .background {
                    self.glassCircleBackground(
                        size: 44,
                        tint: self.glassWhiteTint(light: 0.20, dark: 0.14)
                    )
                }
        }
        .buttonStyle(.plain)
    }

    private var composerControlBar: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(self.composerModelDescriptors) { model in
                    Button {
                        self.selectedComposerModel = model.model
                    } label: {
                        if model.model == self.composerModelForRequest {
                            Label(model.displayName, systemImage: "checkmark")
                        } else {
                            Text(model.displayName)
                        }
                    }
                }
            } label: {
                self.composerPickerChip(self.composerModelDisplayName, minWidth: 140)
            }
            .buttonStyle(.plain)
            .disabled(!self.isComposerInteractive)
            .opacity(self.isComposerInteractive ? 1 : 0.68)

            Menu {
                ForEach(self.composerReasoningOptions) { effort in
                    Button {
                        self.selectedComposerReasoning = effort.value
                    } label: {
                        if effort.value == self.selectedComposerReasoning {
                            Label(effort.displayName, systemImage: "checkmark")
                        } else {
                            Text(effort.displayName)
                        }
                    }
                }
            } label: {
                self.composerPickerChip(self.composerReasoningDisplayName, minWidth: 76)
            }
            .buttonStyle(.plain)
            .disabled(!self.isComposerInteractive)
            .opacity(self.isComposerInteractive ? 1 : 0.68)

            Button {
                self.presentCommandPalette()
            } label: {
                self.composerPickerChip("/", minWidth: 48)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Slash Commands")
            .disabled(!self.isCommandPaletteAvailable)
            .opacity(self.isCommandPaletteAvailable ? 1 : 0.68)

            Spacer(minLength: 8)

            if self.isPromptFieldFocused {
                self.composerKeyboardDismissButton
            }
        }
    }

    private var commandPalettePanel: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                if self.isCommandPaletteSubpanelPresented {
                    Button {
                        self.handleCommandPaletteBackAction()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.92))
                    }
                    .buttonStyle(.plain)
                }

                Text(self.commandPaletteTitle)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.white)

                Spacer(minLength: 8)

                if self.isCommandPaletteRefreshing, !self.isCommandPaletteSubpanelPresented {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.white.opacity(0.9))
                }

                Button("Close") {
                    self.dismissCommandPalette()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.92))
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            if self.isReviewModePickerPresented {
                self.reviewModePickerPanelBody
            } else if self.pendingUserInputRequest != nil {
                self.pendingUserInputPanelBody
            } else if self.commandPaletteRows.isEmpty, !self.isCommandPaletteRefreshing {
                Text("No commands, MCP servers, or skills available")
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.72))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: self.commandPalettePanelMinHeight,
                        maxHeight: .infinity,
                        alignment: .topLeading
                    )
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(self.commandPaletteRows) { row in
                            self.commandPaletteRowButton(row)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: self.commandPalettePanelMinHeight,
                    maxHeight: self.commandPalettePanelMaxHeight,
                    alignment: .top
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            self.glassCardBackground(cornerRadius: 20, tint: self.glassWhiteTint(light: 0.16, dark: 0.10))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(self.glassStrokeColor.opacity(0.5), lineWidth: 0.9)
        }
    }

    private var reviewModePickerPanelBody: some View {
        ScrollView {
            VStack(spacing: 10) {
                self.reviewModeOptionButton(
                    title: "Review uncommitted changes",
                    subtitle: "Start review in a new thread.",
                    systemImage: "doc.badge.magnifyingglass",
                    isSelected: self.reviewModeSelection == .uncommittedChanges
                ) {
                    self.dismissCommandPalette()
                    self.startReviewForCurrentThread(target: .uncommittedChanges)
                }

                self.reviewModeOptionButton(
                    title: "Review against a base branch",
                    subtitle: "Diff against the branch you specify.",
                    systemImage: "arrow.triangle.branch",
                    isSelected: self.reviewModeSelection == .baseBranch
                ) {
                    self.reviewModeSelection = .baseBranch
                    self.isReviewBaseBranchFieldFocused = true
                }

                if self.reviewModeSelection == .baseBranch {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Base branch")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.8))

                        TextField("main", text: self.$reviewBaseBranch)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .focused(self.$isReviewBaseBranchFieldFocused)
                            .foregroundStyle(Color.white)
                            .tint(Color.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.white.opacity(0.07))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
                            )

                        Button("Start review") {
                            self.startReviewAgainstBaseBranch()
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white, in: Capsule())
                        .buttonStyle(.plain)
                        .disabled(self.reviewBaseBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .opacity(
                            self.reviewBaseBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: self.commandPalettePanelMinHeight,
            maxHeight: self.commandPalettePanelMaxHeight,
            alignment: .top
        )
    }

    private var commandPaletteTitle: String {
        if self.isReviewModePickerPresented {
            return "Code Review"
        }
        if self.pendingUserInputRequest != nil {
            return "Input Required"
        }
        return "Commands"
    }

    private var pendingUserInputPanelBody: some View {
        ScrollView {
            VStack(spacing: 10) {
                if self.pendingUserInputQuestions.isEmpty {
                    Text("No input questions available.")
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.72))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                } else {
                    ForEach(self.pendingUserInputQuestions) { question in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(question.prompt)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.white.opacity(0.82))
                                .frame(maxWidth: .infinity, alignment: .leading)

                            ForEach(question.options.indices, id: \.self) { index in
                                let option = question.options[index]
                                self.reviewModeOptionButton(
                                    title: option.label,
                                    subtitle: option.description.isEmpty ? "Select this answer." : option.description,
                                    systemImage: "questionmark.circle",
                                    isSelected: self.pendingUserInputAnswers[question.id] == option.label
                                ) {
                                    self.pendingUserInputAnswers[question.id] = option.label
                                }
                            }

                            TextField("Answer", text: Binding(
                                get: { self.pendingUserInputAnswers[question.id] ?? "" },
                                set: { self.pendingUserInputAnswers[question.id] = $0 }
                            ))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .foregroundStyle(Color.white)
                            .tint(Color.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.white.opacity(0.07))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
                            )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                        )
                    }

                    if !self.pendingUserInputSubmitError.isEmpty {
                        Text(self.pendingUserInputSubmitError)
                            .font(.caption)
                            .foregroundStyle(Color.red.opacity(0.9))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.red.opacity(0.14))
                            )
                    }

                    Button(self.isSubmittingPendingUserInput ? "Submitting..." : "Submit") {
                        self.submitPendingUserInputAnswers()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white, in: Capsule())
                    .buttonStyle(.plain)
                    .disabled(self.pendingUserInputRequest == nil || self.isSubmittingPendingUserInput)
                    .opacity(self.pendingUserInputRequest == nil || self.isSubmittingPendingUserInput ? 0.45 : 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 2)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: self.commandPalettePanelMinHeight,
            maxHeight: self.commandPalettePanelMaxHeight,
            alignment: .top
        )
    }

    private func reviewModeOptionButton(
        title: String,
        subtitle: String,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.86))
                    .frame(width: 20, height: 20)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.94))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.62))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.12 : 0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(isSelected ? 0.20 : 0.12), lineWidth: 0.7)
            )
        }
        .buttonStyle(.plain)
    }

    private var statusPanel: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Text("Status")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.white)

                Spacer(minLength: 8)

                if self.isStatusRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.white.opacity(0.9))
                }

                Button("Refresh") {
                    self.refreshStatusPanel()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.92))

                Button("Close") {
                    self.dismissStatusPanel()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.92))
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            if let snapshot = self.statusSnapshot {
                VStack(alignment: .leading, spacing: 12) {
                    self.statusHeaderRow(label: "Session", value: snapshot.sessionID)
                    self.statusHeaderRow(label: "Context", value: self.statusContextSummary(snapshot))

                    if snapshot.limits.isEmpty {
                        Text("No rate-limit data available")
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.66))
                    } else {
                        ForEach(snapshot.limits) { limit in
                            self.statusLimitRow(limit)
                        }
                    }

                    HStack(spacing: 8) {
                        Text("Updated: \(snapshot.updatedAt.formatted(date: .omitted, time: .shortened))")
                        Spacer(minLength: 8)
                        Text(snapshot.fallbackStatus.uppercased())
                    }
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.58))
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, alignment: .top)
            } else {
                Text(self.isStatusRefreshing ? "Refreshing status..." : "No status available")
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.72))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            self.glassCardBackground(cornerRadius: 20, tint: self.glassWhiteTint(light: 0.16, dark: 0.10))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(self.glassStrokeColor.opacity(0.5), lineWidth: 0.9)
        }
    }

    @ViewBuilder
    private func statusHeaderRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(label):")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.white.opacity(0.70))
                .frame(minWidth: 62, alignment: .leading)

            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.94))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.tail)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func statusLimitRow(_ limit: StatusLimitBarSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("\(limit.label):")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.70))
                    .frame(minWidth: 62, alignment: .leading)

                Spacer(minLength: 8)

                Text(self.statusLimitRemainingText(limit))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.94))

                if let resetText = self.statusLimitResetText(limit.resetAt) {
                    Text("(resets \(resetText))")
                        .font(.caption2)
                        .foregroundStyle(Color.white.opacity(0.58))
                }
            }

            GeometryReader { proxy in
                let fillFraction = self.statusLimitFillFraction(limit.remainingPercent)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.white.opacity(0.17))

                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.white.opacity(0.92))
                        .frame(width: proxy.size.width * fillFraction)
                }
            }
            .frame(height: 10)
        }
    }

    private func statusContextSummary(_ snapshot: StatusPanelSnapshot) -> String {
        guard let used = snapshot.contextUsedTokens,
              let max = snapshot.contextMaxTokens,
              max > 0 else {
            return "Unavailable"
        }
        let usedText = self.groupedTokenCount(used)
        let maxText = self.compactTokenCount(max)
        if let remainingPercent = snapshot.contextRemainingPercent {
            return "\(Int(remainingPercent.rounded()))% left (\(usedText) used / \(maxText))"
        }
        return "\(usedText) used / \(maxText)"
    }

    private func statusLimitRemainingText(_ limit: StatusLimitBarSnapshot) -> String {
        guard let remainingPercent = limit.remainingPercent else {
            return "unknown"
        }
        return "\(Int(remainingPercent.rounded()))% left"
    }

    private func statusLimitResetText(_ resetAt: Date?) -> String? {
        guard let resetAt else { return nil }
        if Calendar.current.isDate(resetAt, inSameDayAs: Date()) {
            return resetAt.formatted(date: .omitted, time: .shortened)
        }
        return resetAt.formatted(Date.FormatStyle().month().day())
    }

    private func statusLimitFillFraction(_ remainingPercent: Double?) -> CGFloat {
        guard let remainingPercent else {
            return 0
        }
        let normalized = max(0, min(100, remainingPercent)) / 100
        return CGFloat(normalized)
    }

    private func groupedTokenCount(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    private func compactTokenCount(_ value: Int) -> String {
        let absolute = abs(value)
        if absolute >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if absolute >= 1_000 {
            return String(format: "%.0fK", Double(value) / 1_000)
        }
        return value.formatted()
    }

    private func commandPaletteRowButton(_ row: CommandPaletteRow) -> some View {
        let metadata = self.commandPaletteMetadata(for: row)
        let disabled = self.isCommandPaletteRowDisabled(row)

        return Button {
            self.handleCommandPaletteSelection(row)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: metadata.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.86))
                    .frame(width: 20, height: 20)

                VStack(alignment: .leading, spacing: 3) {
                    Text(metadata.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.94))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let subtitle = metadata.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.62))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(self.commandPaletteSubtitleLineLimit(for: row))
                            .truncationMode(.tail)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.7)
            )
            .opacity(disabled ? 0.48 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func commandPaletteMetadata(for row: CommandPaletteRow) -> (title: String, subtitle: String?, systemImage: String) {
        switch row {
        case .command(let command):
            return (command.title, command.description, command.systemImage)
        case .mcp(let server):
            let status = server.authStatus ?? "unknown"
            return (
                server.name,
                "MCP server • tools \(server.toolCount) • resources \(server.resourceCount) • auth \(status)",
                "shippingbox"
            )
        case .skill(let skill):
            let description = skill.description?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (
                skill.name,
                (description?.isEmpty == false) ? description : "Skill",
                "sparkles"
            )
        }
    }

    private func commandPaletteSubtitleLineLimit(for row: CommandPaletteRow) -> Int? {
        switch row {
        case .skill:
            return 1
        case .command, .mcp:
            return nil
        }
    }

    private func isCommandPaletteRowDisabled(_ row: CommandPaletteRow) -> Bool {
        switch row {
        case .command(let command):
            return self.isSlashCommandDisabled(command)
        case .mcp, .skill:
            return false
        }
    }

    private var chatComposer: some View {
        let isInactive = !self.isComposerInteractive

        return VStack(alignment: .leading, spacing: 8) {
            if self.isStatusPanelPresented {
                self.statusPanel
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if self.isCommandPalettePresented {
                self.commandPalettePanel
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            self.composerControlBar

            VStack(alignment: .leading, spacing: 8) {
                if self.isPlanModeEnabled {
                    Button {
                        self.disablePlanMode()
                    } label: {
                        HStack(spacing: 6) {
                            Text("Plan")
                                .font(.caption2.weight(.semibold))
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(Color.white.opacity(0.92))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.14))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.20), lineWidth: 0.8)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Disable Plan Mode")
                }

                if !self.composerTokenBadges.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(self.composerTokenBadges) { badge in
                                self.composerTokenBadgeChip(badge)
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                    .frame(height: 28)
                }

                HStack(alignment: .bottom, spacing: 10) {
                    ZStack(alignment: .leading) {
                        if self.prompt.isEmpty {
                            Image(systemName: "sparkles")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.38))
                                .allowsHitTesting(false)
                        }

                        TextField("", text: self.$prompt, axis: .vertical)
                            .lineLimit(1...4)
                            .textInputAutocapitalization(.sentences)
                            .submitLabel(.send)
                            .focused(self.$isPromptFieldFocused)
                            .foregroundStyle(Color.white)
                            .tint(Color.white)
                            .font(.body)
                            .frame(minHeight: 36)
                            .disabled(isInactive)
                            .opacity(isInactive ? 0.72 : 1)
                            .onSubmit {
                                if self.canSendPrompt {
                                    self.sendPrompt(forceNewThread: false)
                                }
                            }
                    }

                    Button {
                        self.isPromptFieldFocused = false
                        self.sendPrompt(forceNewThread: false)
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(isInactive ? Color.white.opacity(0.72) : Color.black)
                            .frame(width: 36, height: 36)
                            .background((isInactive ? Color.white.opacity(0.24) : Color.white), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!self.canSendPrompt)
                    .opacity(self.canSendPrompt ? 1 : 0.45)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                if isInactive {
                    self.glassCardBackground(cornerRadius: 24, tint: self.glassWhiteTint(light: 0.20, dark: 0.12))
                } else {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color(red: 0.14, green: 0.14, blue: 0.16))
                }
            }
            .overlay {
                if isInactive {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(self.glassStrokeColor.opacity(0.62), lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .onTapGesture {
                guard self.isComposerInteractive, self.isPromptEmpty else { return }
                self.isPromptFieldFocused = true
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .background(Color.black)
    }

    @ViewBuilder
    private func chatInfoBanner(
        text: String,
        tone: InfoBannerTone
    ) -> some View {
        let style = self.infoBannerStyle(for: tone)
        Label(text, systemImage: style.icon)
            .font(.caption)
            .foregroundStyle(style.foreground)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(style.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func infoBannerStyle(for tone: InfoBannerTone) -> (icon: String, foreground: Color, background: Color) {
        switch tone {
        case .status:
            return ("checkmark.circle", Color.white.opacity(0.78), Color.white.opacity(0.08))
        case .success:
            return ("checkmark.circle.fill", Color.white.opacity(0.88), Color.green.opacity(0.18))
        case .error:
            return ("exclamationmark.triangle.fill", .red, Color.red.opacity(0.12))
        }
    }

    private func chatStreamingStatusRow(baseText: String) -> some View {
        TimelineView(.periodic(from: .now, by: 0.45)) { context in
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.white.opacity(0.85))

                Text(self.animatedStreamingStatus(baseText: baseText, date: context.date))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.82))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    @ViewBuilder
    private func chatPlaceholder(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Color.white.opacity(0.62))
            .frame(maxWidth: .infinity, minHeight: 200, alignment: .center)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private func chatMessageRow(_ message: SessionChatMessage) -> some View {
        if message.role == .assistant {
            let assistantForeground = message.isProgressDetail
                ? Color.white.opacity(0.62)
                : Color.white
            self.assistantMarkdownView(
                message.text,
                isProgressDetail: message.isProgressDetail
            )
                .foregroundStyle(assistantForeground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .tint(Color.blue.opacity(0.94))
        } else {
            HStack {
                Spacer(minLength: 48)
                InlineText(markdown: self.normalizedMarkdown(message.text))
                    .font(.subheadline)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .textSelection(.enabled)
                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .frame(maxWidth: 300, alignment: .trailing)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func assistantMarkdownView(
        _ text: String,
        isProgressDetail: Bool
    ) -> some View {
        if isProgressDetail {
            InlineText(markdown: self.normalizedMarkdown(text))
                .font(.footnote)
        } else {
            StructuredText(markdown: self.normalizedMarkdown(text))
                .font(.body)
        }
    }

    private func normalizedMarkdown(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
    }

    private var sideMenu: some View {
        GeometryReader { proxy in
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(self.host.name)
                            .font(.headline)
                            .lineLimit(1)
                        Text(self.host.appServerURL)
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
                    VStack(spacing: 10) {
                        Text("Project")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 2)
                            .padding(.top, 2)

                        if self.workspaces.isEmpty {
                            Text("No projects.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 14)
                                .background {
                                    self.glassCardBackground(cornerRadius: 14)
                                }
                        } else {
                            Menu {
                                ForEach(self.workspaces) { workspace in
                                    Button {
                                        self.isPromptFieldFocused = false
                                        self.selectWorkspace(workspace)
                                    } label: {
                                        if workspace.id == self.selectedWorkspaceID {
                                            Label(workspace.displayName, systemImage: "checkmark")
                                        } else {
                                            Text(workspace.displayName)
                                        }
                                    }
                                }

                                Divider()

                                Button {
                                    self.editingWorkspace = nil
                                    self.isPresentingProjectEditor = true
                                    self.isMenuOpen = false
                                } label: {
                                    Label("Add Project", systemImage: "plus")
                                }

                                if let selectedWorkspace {
                                    Button(role: .destructive) {
                                        self.workspacePendingDeletion = selectedWorkspace
                                        self.isMenuOpen = false
                                    } label: {
                                        Label("Delete Project", systemImage: "trash")
                                    }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Text(self.selectedWorkspace?.displayName ?? "Select project")
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background {
                                    self.glassCardBackground(
                                        cornerRadius: 14,
                                        tint: self.accentGlassTint(light: 0.18, dark: 0.14)
                                    )
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        Text("Threads")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 2)
                            .padding(.top, 4)

                        Button {
                            self.isPromptFieldFocused = false
                            self.createNewThread()
                            self.isMenuOpen = false
                        } label: {
                            Label("New Thread", systemImage: "plus.bubble")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background {
                                    self.glassCardBackground(cornerRadius: 14, tint: self.accentGlassTint(light: 0.16, dark: 0.12))
                                }
                        }
                        .buttonStyle(.plain)
                        .disabled(self.selectedWorkspace == nil || self.isRunningSSHAction)
                        .opacity(self.selectedWorkspace == nil ? 0.5 : 1)

                        if self.selectedWorkspace == nil {
                            Text("Select a project.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                        } else if self.selectedWorkspaceThreads.isEmpty {
                            Text("No threads")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                        } else {
                            VStack(spacing: 6) {
                                ForEach(self.selectedWorkspaceThreads) { summary in
                                    Button {
                                        if let selectedWorkspaceID {
                                            self.selectThread(summary, workspaceID: selectedWorkspaceID)
                                        }
                                    } label: {
                                        HStack(spacing: 8) {
                                            Text(summary.preview.isEmpty ? "New Thread" : summary.preview)
                                                .font(.subheadline.weight(self.selectedThreadID == summary.threadID ? .semibold : .regular))
                                                .lineLimit(1)
                                            Spacer(minLength: 8)
                                        }
                                        .foregroundStyle(
                                            self.selectedThreadID == summary.threadID
                                            ? Color.accentColor
                                            : Color.primary
                                        )
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background {
                                            if self.selectedThreadID == summary.threadID {
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .fill(Color.accentColor.opacity(self.isDarkMode ? 0.18 : 0.12))
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            self.archiveThread(summary: summary, archived: true)
                                        } label: {
                                            Label("Archive", systemImage: "archivebox")
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }

                VStack(spacing: 8) {
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

                    Button {
                        self.isMenuOpen = false
                        self.dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.left")
                            Text("Back to hosts")
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
            .padding(.top, max(proxy.safeAreaInsets.top, self.windowSafeAreaTopInset) + 12)
            .padding(.bottom, proxy.safeAreaInsets.bottom + 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: self.menuWidth)
        .background(Color(.systemBackground))
        .ignoresSafeArea(.container, edges: .vertical)
        .offset(x: self.isMenuOpen ? 0 : -(self.menuWidth + 20))
        .shadow(color: .black.opacity(self.isMenuOpen ? 0.14 : 0), radius: 16, x: 0, y: 10)
        .gesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    guard value.translation.width < -48 else { return }
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                        self.isMenuOpen = false
                    }
                }
        )
    }

    private var menuEdgeOpenHandle: some View {
        Color.clear
            .frame(width: 22)
            .contentShape(Rectangle())
            .ignoresSafeArea(.container, edges: .vertical)
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onEnded { value in
                        guard value.startLocation.x < 28,
                              value.translation.width > 52 else {
                            return
                        }
                        self.isPromptFieldFocused = false
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                            self.isMenuOpen = true
                        }
                    }
            )
    }

    @ViewBuilder
    private func glassCardBackground(cornerRadius: CGFloat, tint: Color? = nil) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let resolvedTint = tint ?? self.glassWhiteTint(light: 0.18, dark: 0.10)
        if #available(iOS 26.0, *) {
            shape
                .fill(resolvedTint)
                .glassEffect(.regular, in: shape)
        } else {
            shape
                .fill(.ultraThinMaterial)
                .overlay(
                    shape.strokeBorder(self.glassStrokeColor, lineWidth: 0.8)
                )
        }
    }

    @ViewBuilder
    private func glassCircleBackground(size: CGFloat, tint: Color? = nil) -> some View {
        let circle = Circle()
        let resolvedTint = tint ?? self.glassWhiteTint(light: 0.20, dark: 0.12)
        if #available(iOS 26.0, *) {
            circle
                .fill(resolvedTint)
                .glassEffect(.regular, in: circle)
                .frame(width: size, height: size)
        } else {
            circle
                .fill(.ultraThinMaterial)
                .overlay(
                    circle.strokeBorder(self.glassStrokeColor, lineWidth: 0.8)
                )
                .frame(width: size, height: size)
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo("chat-bottom", anchor: .bottom)
            }
        }
    }

    private func distanceToChatBottom(from geometry: ScrollGeometry) -> CGFloat {
        let visibleBottomY = geometry.contentOffset.y + geometry.containerSize.height
        let distance = geometry.contentSize.height - visibleBottomY
        return max(0, distance)
    }

    private func selectWorkspace(_ workspace: ProjectWorkspace) {
        let previousWorkspaceID = self.selectedWorkspaceID
        self.selectedWorkspaceID = workspace.id
        if previousWorkspaceID != workspace.id {
            self.selectedThreadID = nil
            self.appState.hostSessionStore.selectThread(hostID: self.host.id, threadID: nil)
        }
        self.appState.hostSessionStore.selectProject(hostID: self.host.id, projectID: workspace.id)
        self.refreshThreads()
    }

    private func selectThread(_ summary: CodexThreadSummary, workspaceID: UUID) {
        self.selectedWorkspaceID = workspaceID
        self.selectedThreadID = summary.threadID
        self.appState.hostSessionStore.selectProject(hostID: self.host.id, projectID: workspaceID)
        self.appState.hostSessionStore.selectThread(hostID: self.host.id, threadID: summary.threadID)
        self.applyComposerSelection(model: summary.model, reasoningEffort: summary.reasoningEffort)
        self.loadThread(summary.threadID)
        self.isMenuOpen = false
    }

    private func createNewThread() {
        self.localErrorMessage = ""
        self.localStatusMessage = ""

        guard let selectedWorkspace else {
            self.localErrorMessage = "Select a project first."
            return
        }

        self.appState.hostSessionStore.selectProject(hostID: self.host.id, projectID: selectedWorkspace.id)
        self.selectedThreadID = nil
        self.appState.hostSessionStore.selectThread(hostID: self.host.id, threadID: nil)
        self.showComposerInfo("Ready for a new thread. Send a prompt to start.")
    }

    private func deleteWorkspace(_ workspace: ProjectWorkspace) {
        let replacementWorkspaceID = self.workspaces
            .filter { $0.id != workspace.id }
            .map(\.id)
            .first

        self.appState.removeWorkspace(
            hostID: self.host.id,
            workspaceID: workspace.id,
            replacementWorkspaceID: replacementWorkspaceID
        )

        if self.selectedWorkspaceID == workspace.id {
            self.selectedWorkspaceID = replacementWorkspaceID
            self.selectedThreadID = nil
        }

        self.workspacePendingDeletion = nil
        self.localErrorMessage = ""
        self.localStatusMessage = "Project deleted."
    }

    private func syncComposerControlsWithWorkspace() {
        let selectedModel = self.selectedComposerModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !selectedModel.isEmpty {
            self.syncComposerReasoningWithModel()
            return
        }

        let workspaceDefault = self.selectedWorkspace?.defaultModel
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !workspaceDefault.isEmpty {
            self.selectedComposerModel = workspaceDefault
        } else if let defaultModel = self.appState.appServerClient.availableModels.first(where: { $0.isDefault })?.model {
            self.selectedComposerModel = defaultModel
        } else {
            let currentModel = self.appState.appServerClient.diagnostics.currentModel
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !currentModel.isEmpty {
                self.selectedComposerModel = currentModel
            }
        }

        self.syncComposerReasoningWithModel()
    }

    private func syncComposerReasoningWithModel() {
        let normalizedCurrent = self.selectedComposerReasoning.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let options = self.composerReasoningOptions
        guard !options.isEmpty else { return }

        if options.contains(where: { $0.value == normalizedCurrent }) {
            self.selectedComposerReasoning = normalizedCurrent
            return
        }

        if let defaultEffort = self.selectedComposerModelDescriptor?.defaultReasoningEffort,
           options.contains(where: { $0.value == defaultEffort }) {
            self.selectedComposerReasoning = defaultEffort
            return
        }

        self.selectedComposerReasoning = options[0].value
    }

    private func applyComposerSelection(model: String?, reasoningEffort: String?) {
        let normalizedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedReasoning = reasoningEffort?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard (normalizedModel?.isEmpty == false) || (normalizedReasoning?.isEmpty == false) else {
            return
        }

        if let normalizedModel,
           !normalizedModel.isEmpty {
            self.selectedComposerModel = normalizedModel
        }

        if let normalizedReasoning,
           !normalizedReasoning.isEmpty {
            self.selectedComposerReasoning = normalizedReasoning
        }

        self.syncComposerReasoningWithModel()
    }

    private func updateThreadBookmarkSettings(threadID: String, model: String?, reasoningEffort: String?) {
        guard let selectedWorkspaceID else { return }
        guard var summary = self.appState.threadBookmarkStore
            .threads(for: selectedWorkspaceID)
            .first(where: { $0.threadID == threadID }) else {
            return
        }

        var didChange = false

        if let normalizedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines),
           !normalizedModel.isEmpty,
           summary.model != normalizedModel {
            summary.model = normalizedModel
            didChange = true
        }

        if let normalizedReasoning = reasoningEffort?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !normalizedReasoning.isEmpty,
           summary.reasoningEffort != normalizedReasoning {
            summary.reasoningEffort = normalizedReasoning
            didChange = true
        }

        if didChange {
            self.appState.threadBookmarkStore.upsert(summary: summary)
        }
    }

    private static func parseChatMessages(from transcript: String) -> [SessionChatMessage] {
        let normalized = transcript.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var messages: [SessionChatMessage] = []
        var currentRole: SessionChatRole?
        var currentIsProgressDetail = false
        var buffer: [String] = []

        func flushCurrent() {
            guard let currentRole else { return }
            let text = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            messages.append(
                SessionChatMessage(
                    id: "msg-\(messages.count)",
                    role: currentRole,
                    text: text,
                    isProgressDetail: currentIsProgressDetail
                )
            )
        }

        for line in lines {
            if line.hasPrefix("=== Turn ") {
                flushCurrent()
                currentRole = nil
                currentIsProgressDetail = false
                buffer = []
                continue
            }

            if line.hasPrefix("User: ") {
                flushCurrent()
                currentRole = .user
                currentIsProgressDetail = false
                buffer = [String(line.dropFirst("User: ".count))]
                continue
            }

            if line.hasPrefix("Assistant: ") {
                flushCurrent()
                currentRole = .assistant
                currentIsProgressDetail = false
                buffer = [String(line.dropFirst("Assistant: ".count))]
                continue
            }

            if line.hasPrefix("Plan: ")
                || line.hasPrefix("Reasoning: ")
                || line.hasPrefix("Item: ") {
                flushCurrent()
                currentRole = .assistant
                currentIsProgressDetail = true
                let detailContent = Self.progressDetailContent(from: line)
                buffer = detailContent.isEmpty ? [] : [detailContent]
                continue
            }

            if line.hasPrefix("$ ")
                || line.hasPrefix("File change ") {
                flushCurrent()
                currentRole = .assistant
                currentIsProgressDetail = true
                buffer = [line]
                continue
            }

            if line.isEmpty {
                if currentRole != nil && !buffer.isEmpty {
                    buffer.append("")
                }
                continue
            }

            if currentRole != nil {
                buffer.append(line)
            }
        }

        flushCurrent()
        return messages
    }

    private static func progressDetailContent(from line: String) -> String {
        guard let colonIndex = line.firstIndex(of: ":") else {
            return line
        }
        var content = line[line.index(after: colonIndex)...]
        if content.first == " " {
            content = content.dropFirst()
        }
        return String(content)
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

        if let selectedThreadID = session?.selectedThreadID,
           !selectedThreadID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.selectedThreadID = selectedThreadID
        } else {
            self.selectedThreadID = nil
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
                await self.appState.appServerClient.refreshCatalogs(primaryCWD: self.selectedWorkspace?.remotePath)
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

                let fetched = try await self.appState.appServerClient.threadList(archived: false, limit: 300)
                let scoped = fetched.filter { $0.cwd == selectedWorkspace.remotePath }
                let existingByThreadID = Dictionary(
                    uniqueKeysWithValues: self.appState.threadBookmarkStore
                        .threads(for: selectedWorkspace.id)
                        .map { ($0.threadID, $0) }
                )
                let summaries: [CodexThreadSummary] = scoped.map { thread in
                    let existing = existingByThreadID[thread.id]
                    return CodexThreadSummary(
                        threadID: thread.id,
                        hostID: self.host.id,
                        workspaceID: selectedWorkspace.id,
                        preview: thread.preview,
                        updatedAt: thread.updatedAt,
                        archived: thread.archived,
                        cwd: thread.cwd,
                        model: thread.model ?? existing?.model,
                        reasoningEffort: thread.reasoningEffort ?? existing?.reasoningEffort
                    )
                }

                self.appState.threadBookmarkStore.replaceThreads(
                    for: selectedWorkspace.id,
                    hostID: self.host.id,
                    with: summaries
                )

                let selectedWorkspaceThreads = self.threads(for: selectedWorkspace.id)
                if let selectedThreadID = self.selectedThreadID,
                   selectedWorkspaceThreads.contains(where: { $0.threadID == selectedThreadID }) {
                    self.loadThread(selectedThreadID)
                } else if self.selectedThreadID != nil {
                    self.selectedThreadID = nil
                    self.appState.hostSessionStore.selectThread(hostID: self.host.id, threadID: nil)
                }
            } catch {
                self.localErrorMessage = self.appState.appServerClient.userFacingMessage(for: error)
            }
        }
    }

    private func sendPrompt(forceNewThread: Bool) {
        let originalPrompt = self.prompt
        let originalTokenBadges = self.selectedComposerTokenBadges
        let trimmedPrompt = self.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return }
        let promptForRequest = self.composePromptForRequest(from: trimmedPrompt)
        guard let selectedWorkspace else {
            self.localErrorMessage = "Select a project first."
            return
        }

        self.localErrorMessage = ""
        self.localStatusMessage = ""
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
        let shouldConsumePlanModeAfterSend = self.isPlanCollaborationMode(collaborationModeIDForRequest)
        if shouldConsumePlanModeAfterSend {
            self.consumePlanModeAfterSend()
        }

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
                    self.localErrorMessage = "Failed to resolve thread."
                    return
                }

                self.selectedThreadID = threadID
                self.appState.hostSessionStore.selectThread(hostID: self.host.id, threadID: threadID)

                var selectedModelForThread = self.selectedThreadSummary?.model
                var selectedReasoningForThread = self.selectedThreadSummary?.reasoningEffort
                if let activeTurnID = self.appState.appServerClient.activeTurnID(for: threadID) {
                    try await self.appState.appServerClient.turnSteer(
                        threadID: threadID,
                        expectedTurnID: activeTurnID,
                        inputText: promptForRequest
                    )
                } else {
                    _ = try await self.appState.appServerClient.turnStart(
                        threadID: threadID,
                        inputText: promptForRequest,
                        model: self.composerModelForRequest,
                        effort: self.selectedComposerReasoning,
                        collaborationModeID: collaborationModeIDForRequest
                    )
                    selectedModelForThread = self.composerModelForRequest
                    selectedReasoningForThread = self.selectedComposerReasoning
                }

                self.appState.appServerClient.appendLocalEcho(promptForRequest, to: threadID)

                self.appState.threadBookmarkStore.upsert(
                    summary: CodexThreadSummary(
                        threadID: threadID,
                        hostID: self.host.id,
                        workspaceID: selectedWorkspace.id,
                        preview: trimmedPrompt,
                        updatedAt: Date(),
                        archived: false,
                        cwd: selectedWorkspace.remotePath,
                        model: selectedModelForThread,
                        reasoningEffort: selectedReasoningForThread
                    )
                )
            } catch {
                let message = self.appState.appServerClient.userFacingMessage(for: error)
                self.localErrorMessage = message
                self.showComposerInfo(message, tone: .error, autoDismissAfter: 4.0)
                if self.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   self.selectedComposerTokenBadges.isEmpty {
                    self.prompt = originalPrompt
                    self.selectedComposerTokenBadges = originalTokenBadges
                    self.isPromptFieldFocused = true
                }
            }
        }
    }

    private func presentCommandPalette() {
        guard self.isCommandPaletteAvailable else { return }
        if self.isCommandPalettePresented {
            self.dismissCommandPalette()
            return
        }
        self.dismissStatusPanel()
        self.dismissReviewModePicker()
        self.dismissPendingUserInputPanel()
        self.isCommandPalettePresented = true
        self.refreshCommandPalette()
    }

    private func dismissCommandPalette() {
        self.isCommandPalettePresented = false
        self.dismissReviewModePicker()
        self.dismissPendingUserInputPanel()
    }

    private func presentReviewModePicker() {
        guard self.isCommandPalettePresented else {
            self.localErrorMessage = "Open commands and select /review again."
            return
        }
        self.dismissPendingUserInputPanel()
        self.reviewModeSelection = .uncommittedChanges
        self.reviewBaseBranch = ""
        self.isReviewModePickerPresented = true
    }

    private func dismissReviewModePicker() {
        self.isReviewModePickerPresented = false
        self.reviewModeSelection = .uncommittedChanges
        self.reviewBaseBranch = ""
        self.isReviewBaseBranchFieldFocused = false
    }

    private func presentPendingUserInputPanel(_ request: AppServerPendingRequest) {
        guard case .userInput(let questions) = request.kind else {
            return
        }
        self.dismissStatusPanel()
        self.dismissReviewModePicker()
        self.pendingUserInputRequest = request
        self.pendingUserInputSubmitError = ""
        self.isSubmittingPendingUserInput = false
        self.pendingUserInputAnswers = Dictionary(uniqueKeysWithValues: questions.map { question in
            let defaultAnswer = question.options.first?.label ?? ""
            return (question.id, defaultAnswer)
        })
        self.isCommandPalettePresented = true
    }

    private func dismissPendingUserInputPanel() {
        self.pendingUserInputRequest = nil
        self.pendingUserInputAnswers = [:]
        self.pendingUserInputSubmitError = ""
        self.isSubmittingPendingUserInput = false
    }

    private func handlePendingRequestsUpdated() {
        let pendingRequests = self.appState.appServerClient.pendingRequests

        if let activeRequest = self.pendingUserInputRequest,
           pendingRequests.contains(where: { $0.id == activeRequest.id }) == false {
            self.dismissPendingUserInputPanel()
        }

        if self.shouldPresentNextUserInputPanelAfterPlan,
           let userInputRequest = pendingRequests.first(where: { request in
               if case .userInput = request.kind {
                   return true
               }
               return false
           }) {
            self.shouldPresentNextUserInputPanelAfterPlan = false
            self.presentPendingUserInputPanel(userInputRequest)
        }
    }

    private func presentFirstPendingRequest() {
        if let userInputRequest = self.appState.appServerClient.pendingRequests.first(where: { request in
            if case .userInput = request.kind {
                return true
            }
            return false
        }) {
            self.presentPendingUserInputPanel(userInputRequest)
            return
        }

        self.activePendingRequest = self.appState.appServerClient.pendingRequests.first
    }

    private func submitPendingUserInputAnswers() {
        guard let request = self.pendingUserInputRequest,
              case .userInput(let questions) = request.kind else {
            return
        }

        self.pendingUserInputSubmitError = ""
        self.isSubmittingPendingUserInput = true

        var answers: [String: [String]] = [:]
        for question in questions {
            let raw = self.pendingUserInputAnswers[question.id, default: ""]
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
            defer {
                self.isSubmittingPendingUserInput = false
            }
            do {
                try await self.appState.appServerClient.respondUserInput(request: request, answers: answers)
                self.dismissCommandPalette()
                self.showComposerInfo("Submitted input.", tone: .status)
            } catch {
                self.pendingUserInputSubmitError = self.appState.appServerClient.userFacingMessage(for: error)
            }
        }
    }

    private func handleCommandPaletteBackAction() {
        if self.isReviewModePickerPresented {
            self.dismissReviewModePicker()
            return
        }
        if self.pendingUserInputRequest != nil {
            self.dismissPendingUserInputPanel()
        }
    }

    private func refreshCommandPalette() {
        guard !self.isSSHTransport else { return }
        self.isCommandPaletteRefreshing = true

        Task {
            defer {
                self.isCommandPaletteRefreshing = false
            }
            do {
                try await self.ensureAppServerReady(refreshCatalogs: true)
            } catch {
                self.localErrorMessage = self.appState.appServerClient.userFacingMessage(for: error)
            }
        }
    }

    private func presentStatusPanel() {
        guard !self.isSSHTransport else {
            self.localErrorMessage = "Slash commands are only available in App Server mode."
            return
        }
        self.dismissCommandPalette()
        self.isStatusPanelPresented = true
        self.statusSnapshot = self.makeStatusSnapshot()
        self.refreshStatusPanel()
    }

    private func dismissStatusPanel() {
        self.isStatusPanelPresented = false
    }

    private func refreshStatusPanel() {
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
                self.localErrorMessage = self.appState.appServerClient.userFacingMessage(for: error)
            }
        }
    }

    private func showComposerInfo(
        _ text: String,
        tone: InfoBannerTone = .success,
        autoDismissAfter seconds: TimeInterval = 2.5
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        self.composerInfoDismissTask?.cancel()
        let message = ComposerInfoMessage(text: trimmed, tone: tone)
        self.composerInfoMessage = message

        let nanos = UInt64(max(0, seconds) * 1_000_000_000)
        self.composerInfoDismissTask = Task {
            if nanos > 0 {
                try? await Task.sleep(nanoseconds: nanos)
            }
            guard !Task.isCancelled else { return }
            if self.composerInfoMessage?.id == message.id {
                self.composerInfoMessage = nil
            }
            self.composerInfoDismissTask = nil
        }
    }

    private func clearComposerInfo() {
        self.composerInfoDismissTask?.cancel()
        self.composerInfoDismissTask = nil
        self.composerInfoMessage = nil
    }

    private func handleCommandPaletteSelection(_ row: CommandPaletteRow) {
        switch row {
        case .command(let command):
            if command.kind != .startReview {
                self.dismissCommandPalette()
            }
            self.executeSlashCommand(command)
        case .mcp(let server):
            self.insertComposerToken("/mcp \(server.name)")
            self.dismissCommandPalette()
        case .skill(let skill):
            self.insertComposerToken("$\(skill.name)")
            self.dismissCommandPalette()
        }
    }

    private func insertComposerToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let badge = Self.makeComposerTokenBadge(token: trimmed) else { return }
        let normalized = badge.token.lowercased()
        if !self.selectedComposerTokenBadges.contains(where: { $0.token.lowercased() == normalized }) {
            self.selectedComposerTokenBadges.append(badge)
        }
        self.isPromptFieldFocused = true
    }

    @ViewBuilder
    private func composerTokenBadgeChip(_ badge: ComposerTokenBadge) -> some View {
        let icon = badge.kind == .mcp ? "shippingbox" : "sparkles"
        let background = badge.kind == .mcp ? Color.cyan.opacity(0.20) : Color.green.opacity(0.20)
        let border = badge.kind == .mcp ? Color.cyan.opacity(0.45) : Color.green.opacity(0.45)
        Button {
            self.removeComposerTokenBadge(badge)
        } label: {
            HStack(spacing: 6) {
                Label(badge.title, systemImage: icon)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.94))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.88))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(background, in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(border, lineWidth: 0.9)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove composer token \(badge.token)")
    }

    private func removeComposerTokenBadge(_ badge: ComposerTokenBadge) {
        self.selectedComposerTokenBadges.removeAll { $0.id == badge.id }
    }

    private func composePromptForRequest(from trimmedPrompt: String) -> String {
        guard !self.selectedComposerTokenBadges.isEmpty else {
            return trimmedPrompt
        }
        let prefixes = self.selectedComposerTokenBadges.map(\.token)
        return (prefixes + [trimmedPrompt]).joined(separator: "\n")
    }

    private static func makeComposerTokenBadge(token: String) -> ComposerTokenBadge? {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        if normalized.lowercased().hasPrefix("/mcp") {
            let title = normalized
                .replacingOccurrences(of: "/mcp", with: "MCP", options: [.caseInsensitive])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return ComposerTokenBadge(
                id: "mcp-\(normalized.lowercased())",
                kind: .mcp,
                token: normalized,
                title: title.isEmpty ? "MCP" : title
            )
        }

        if normalized.hasPrefix("$") {
            let skillName = String(normalized.dropFirst())
            return ComposerTokenBadge(
                id: "skill-\(normalized.lowercased())",
                kind: .skill,
                token: normalized,
                title: skillName.isEmpty ? "Skill" : "Skill \(skillName)"
            )
        }

        return nil
    }

    private func executeSlashCommand(_ command: AppServerSlashCommandDescriptor) {
        guard !self.isSSHTransport else {
            self.localErrorMessage = "Slash commands are only available in App Server mode."
            return
        }
        guard !self.isSlashCommandDisabled(command) else {
            self.localErrorMessage = "Select a thread first."
            return
        }

        self.localErrorMessage = ""
        self.localStatusMessage = ""

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
        }
    }

    private func refreshAppServerCatalogsForCurrentWorkspace() {
        guard !self.isSSHTransport else { return }
        Task {
            await self.appState.appServerClient.refreshCatalogs(primaryCWD: self.selectedWorkspace?.remotePath)
        }
    }

    private func ensureAppServerReady(refreshCatalogs: Bool) async throws {
        if self.appState.appServerClient.state != .connected {
            try await self.appState.appServerClient.connect(to: self.host)
        }
        if refreshCatalogs {
            await self.appState.appServerClient.refreshCatalogs(primaryCWD: self.selectedWorkspace?.remotePath)
        }
    }

    private func forkCurrentThread() {
        guard let sourceThreadID = self.selectedThreadID else {
            self.localErrorMessage = "Select a thread first."
            return
        }
        let sourceSummary = self.selectedThreadSummary
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
                self.refreshThreads()
                self.showComposerInfo("Forked thread: \(forkedThreadID)")
            } catch {
                self.localErrorMessage = self.appState.appServerClient.userFacingMessage(for: error)
            }
        }
    }

    private func startReviewAgainstBaseBranch() {
        let trimmedBaseBranch = self.reviewBaseBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBaseBranch.isEmpty else {
            self.localErrorMessage = "Enter a base branch name."
            return
        }
        self.dismissCommandPalette()
        self.startReviewForCurrentThread(
            target: .baseBranch(trimmedBaseBranch),
            preview: "Code review (\(trimmedBaseBranch))",
            successMessage: "Started review against \(trimmedBaseBranch) in a new thread."
        )
    }

    private func startReviewForCurrentThread(
        target: AppServerClient.ReviewTarget,
        preview: String = "Code review",
        successMessage: String = "Started code review in a new thread."
    ) {
        guard let sourceThreadID = self.selectedThreadID else {
            self.localErrorMessage = "Select a thread first."
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
                self.refreshThreads()
                self.showComposerInfo(successMessage)
            } catch {
                self.localErrorMessage = self.appState.appServerClient.userFacingMessage(for: error)
            }
        }
    }

    private func showStatusSlashCommand() {
        self.presentStatusPanel()
    }

    private func startPlanModeSlashCommand() {
        self.composerCollaborationModeID = self.planCollaborationModeID
        self.shouldPresentNextUserInputPanelAfterPlan = true
        self.showComposerInfo("Plan mode enabled. Send a prompt to continue.", tone: .status)
        self.isPromptFieldFocused = true
    }

    private func disablePlanMode() {
        guard self.composerCollaborationModeIDForRequest != nil else { return }
        self.composerCollaborationModeID = ""
        self.shouldPresentNextUserInputPanelAfterPlan = false
        self.showComposerInfo("Plan mode disabled.", tone: .status)
    }

    private func consumePlanModeAfterSend() {
        guard self.isPlanModeEnabled else { return }
        // Keep pending user-input auto-presentation armed for the already-started plan turn.
        self.composerCollaborationModeID = ""
    }

    private func sendPromptViaSSH(
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
                self.localStatusMessage = "Executed via codex exec over SSH."
            } catch {
                self.localErrorMessage = self.userFacingSSHError(error)
            }
        }
    }

    private func appendSSHTranscript(prompt: String, response: String, threadID: String) {
        var existing = self.sshTranscriptByThread[threadID] ?? ""
        if !existing.isEmpty {
            existing += "\n"
        }
        existing += "User: \(prompt)\nAssistant: \(response)"
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
                    model: resolvedModel,
                    reasoningEffort: resolvedReasoning
                )
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
