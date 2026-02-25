import Foundation
import SwiftUI
import Textual

struct SessionWorkbenchView: View {
    enum AssistantStreamingPhase {
        case thinking
        case responding
    }

    enum ReviewModeSelection: String, Equatable {
        case uncommittedChanges
        case baseBranch
    }

    enum InfoBannerTone {
        case status
        case success
        case error
    }

    struct ComposerInfoMessage: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let tone: InfoBannerTone
    }

    struct StatusLimitBarSnapshot: Equatable, Identifiable {
        let id: String
        let label: String
        let remainingPercent: Double?
        let resetAt: Date?
    }

    struct StatusPanelSnapshot: Equatable {
        let sessionID: String
        let contextUsedTokens: Int?
        let contextMaxTokens: Int?
        let contextRemainingPercent: Double?
        let limits: [StatusLimitBarSnapshot]
        let fallbackStatus: String
        let updatedAt: Date
    }

    struct ComposerTokenBadge: Identifiable, Equatable {
        enum Kind: Equatable {
            case mcp
            case skill
        }

        let id: String
        let kind: Kind
        let token: String
        let title: String
    }

    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.scenePhase) var scenePhase

    let host: RemoteHost

    @State var selectedWorkspaceID: UUID?
    @State var selectedThreadID: String?
    @State var prompt = ""
    @State var localErrorMessage = ""
    @State var localStatusMessage = ""
    @State var isRefreshingThreads = false
    @State var isRunningSSHAction = false
    @State var isPresentingProjectEditor = false
    @State var editingWorkspace: ProjectWorkspace?
    @State var workspacePendingDeletion: ProjectWorkspace?
    @State var activePendingRequest: AppServerPendingRequest?
    @State var sshTranscriptByThread: [String: String] = [:]
    @State var isMenuOpen = false
    @State var selectedComposerModel = ""
    @State var selectedComposerReasoning = "low"
    @State var isCommandPalettePresented = false
    @State var isCommandPaletteRefreshing = false
    @State var isReviewModePickerPresented = false
    @State var reviewModeSelection: ReviewModeSelection = .uncommittedChanges
    @State var reviewBaseBranch = ""
    @State var composerCollaborationModeID = ""
    @State var pendingUserInputRequest: AppServerPendingRequest?
    @State var pendingUserInputAnswers: [String: String] = [:]
    @State var pendingUserInputSubmitError = ""
    @State var isSubmittingPendingUserInput = false
    @State var shouldPresentNextUserInputPanelAfterPlan = false
    @State var isStatusPanelPresented = false
    @State var isStatusRefreshing = false
    @State var statusSnapshot: StatusPanelSnapshot?
    @State var composerInfoMessage: ComposerInfoMessage?
    @State var composerInfoDismissTask: Task<Void, Never>?
    @State var selectedComposerTokenBadges: [ComposerTokenBadge] = []
    @State var pendingPromptDispatchCount = 0
    @State var chatDistanceFromBottom: CGFloat = 0
    @State var scrollToBottomRequestCount = 0
    @FocusState var isPromptFieldFocused: Bool
    @FocusState var isReviewBaseBranchFieldFocused: Bool

    let sshCodexExecService = SSHCodexExecService()

    var isSSHTransport: Bool {
        self.host.preferredTransport == .ssh
    }

    var selectedWorkspace: ProjectWorkspace? {
        guard let selectedWorkspaceID else { return nil }
        return self.workspaces.first(where: { $0.id == selectedWorkspaceID })
    }

    var workspaces: [ProjectWorkspace] {
        self.appState.projectStore.workspaces(for: self.host.id)
    }

    var selectedWorkspaceThreads: [CodexThreadSummary] {
        guard let selectedWorkspaceID else { return [] }
        return self.threads(for: selectedWorkspaceID)
    }

    func threads(for workspaceID: UUID) -> [CodexThreadSummary] {
        self.appState.threadBookmarkStore
            .threads(for: workspaceID)
            .filter { !$0.archived }
    }

    var selectedThreadSummary: CodexThreadSummary? {
        guard let selectedWorkspaceID,
              let selectedThreadID else {
            return nil
        }
        return self.threads(for: selectedWorkspaceID).first(where: { $0.threadID == selectedThreadID })
    }

    var selectedThreadTitle: String {
        guard let summary = self.selectedThreadSummary else {
            return "New Thread"
        }
        let title = summary.preview.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "New Thread" : title
    }

    var selectedWorkspaceTitle: String {
        self.selectedWorkspace?.displayName ?? "Project"
    }

    var selectedThreadTranscript: String {
        guard let selectedThreadID else { return "" }
        if self.isSSHTransport {
            return self.sshTranscriptByThread[selectedThreadID] ?? ""
        }
        return self.appState.appServerClient.transcriptByThread[selectedThreadID] ?? ""
    }

    var parsedChatMessages: [SessionChatMessage] {
        Self.parseChatMessages(from: self.selectedThreadTranscript)
    }

    var isPromptEmpty: Bool {
        self.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var composerTokenBadges: [ComposerTokenBadge] {
        self.selectedComposerTokenBadges
    }

    var canSendPrompt: Bool {
        !self.isPromptEmpty
            && !self.isRunningSSHAction
            && self.selectedWorkspace != nil
    }

    var hasVisibleAssistantReplyForLatestPrompt: Bool {
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

    var assistantStreamingPhase: AssistantStreamingPhase? {
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

    func assistantStreamingBaseText(for phase: AssistantStreamingPhase) -> String {
        switch phase {
        case .thinking:
            return "Thinking"
        case .responding:
            return "Generating reply"
        }
    }

    func animatedStreamingStatus(baseText: String, date: Date) -> String {
        let step = Int(date.timeIntervalSinceReferenceDate * 2).quotientAndRemainder(dividingBy: 4).remainder
        let dots = String(repeating: ".", count: max(1, step))
        return baseText + dots
    }

    var shouldShowScrollToBottomButton: Bool {
        self.selectedThreadID != nil && self.chatDistanceFromBottom > 220
    }

    var shouldAutoFollowChatUpdates: Bool {
        self.selectedThreadID != nil && self.chatDistanceFromBottom <= 64
    }

    var isComposerInteractive: Bool {
        !self.isRunningSSHAction && self.selectedWorkspace != nil
    }

    var fallbackReasoningEffortOptions: [CodexReasoningEffortOption] {
        [
            CodexReasoningEffortOption(value: "low", description: nil),
            CodexReasoningEffortOption(value: "medium", description: nil),
            CodexReasoningEffortOption(value: "high", description: nil),
        ]
    }

    var composerModelDescriptors: [AppServerModelDescriptor] {
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

    var composerModelForRequest: String? {
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

    var selectedComposerModelDescriptor: AppServerModelDescriptor? {
        guard let selectedModel = self.composerModelForRequest else { return nil }
        return self.composerModelDescriptors.first(where: { $0.model == selectedModel })
    }

    var composerModelDisplayName: String {
        if let selectedComposerModelDescriptor {
            return selectedComposerModelDescriptor.displayName
        }

        if let defaultModel = self.composerModelDescriptors.first(where: { $0.isDefault }) {
            return defaultModel.displayName
        }

        return "GPT-5.3-Codex"
    }

    var composerReasoningOptions: [CodexReasoningEffortOption] {
        if let selectedComposerModelDescriptor,
           !selectedComposerModelDescriptor.reasoningEffortOptions.isEmpty {
            return selectedComposerModelDescriptor.reasoningEffortOptions
        }
        return self.fallbackReasoningEffortOptions
    }

    var composerReasoningDisplayName: String {
        let selected = self.selectedComposerReasoning.trimmingCharacters(in: .whitespacesAndNewlines)
        if let matched = self.composerReasoningOptions.first(where: { $0.value == selected }) {
            return matched.displayName
        }
        if !selected.isEmpty {
            return CodexReasoningEffortOption(value: selected, description: nil).displayName
        }
        return self.fallbackReasoningEffortOptions.first?.displayName ?? "Low"
    }

    var slashCommandDescriptors: [AppServerSlashCommandDescriptor] {
        guard !self.isSSHTransport else { return [] }
        return self.appState.appServerClient.availableSlashCommands
    }

    var commandPaletteRows: [CommandPaletteRow] {
        buildCommandPaletteRows(
            commands: self.slashCommandDescriptors,
            mcpServers: self.appState.appServerClient.mcpServers,
            skills: self.appState.appServerClient.availableSkills
        )
    }

    var composerCollaborationModeIDForRequest: String? {
        let trimmed = self.composerCollaborationModeID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var planCollaborationModeID: String {
        if let mode = self.appState.appServerClient.availableCollaborationModes.first(where: {
            $0.normalizedID == "plan" || $0.title.lowercased().contains("plan")
        }) {
            return mode.id
        }
        return "plan"
    }

    var isPlanModeEnabled: Bool {
        guard let modeID = self.composerCollaborationModeIDForRequest else {
            return false
        }
        let normalizedModeID = modeID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedPlanID = self.planCollaborationModeID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalizedModeID == "plan" || normalizedModeID == normalizedPlanID
    }

    var isAwaitingPromptDispatch: Bool {
        self.pendingPromptDispatchCount > 0
    }

    func isPlanCollaborationMode(_ modeID: String?) -> Bool {
        guard let modeID else { return false }
        let normalizedModeID = modeID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedModeID.isEmpty else { return false }
        let normalizedPlanID = self.planCollaborationModeID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalizedModeID == "plan" || normalizedModeID == normalizedPlanID
    }

    var isCommandPaletteSubpanelPresented: Bool {
        self.isReviewModePickerPresented || self.pendingUserInputRequest != nil
    }

    var pendingUserInputQuestions: [AppServerUserInputQuestion] {
        guard let request = self.pendingUserInputRequest,
              case .userInput(let questions) = request.kind else {
            return []
        }
        return questions
    }

    var isCommandPaletteAvailable: Bool {
        !self.isSSHTransport && self.isComposerInteractive
    }

    var commandPalettePanelMaxHeight: CGFloat {
        #if canImport(UIKit)
        let screenHeight = UIScreen.main.bounds.height
        return min(620, max(440, screenHeight * 0.72))
        #else
        return 500
        #endif
    }

    var commandPalettePanelMinHeight: CGFloat {
        min(380, self.commandPalettePanelMaxHeight * 0.75)
    }

    func makeStatusSnapshot() -> StatusPanelSnapshot {
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

    func preferredStatusRateLimits(from limits: [AppServerRateLimitSummary]) -> [AppServerRateLimitSummary] {
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

    func statusRateLimitRank(_ limit: AppServerRateLimitSummary) -> Int {
        if let window = limit.windowMinutes {
            if window == 300 { return 0 }
            if window == 10080 { return 1 }
        }
        let name = limit.name.lowercased()
        if name.contains("5h") { return 0 }
        if name.contains("7d") { return 1 }
        return 2
    }

    func statusLimitLabel(for limit: AppServerRateLimitSummary) -> String {
        if let window = limit.windowMinutes {
            if window == 300 { return "5h limit" }
            if window == 10080 { return "7d limit" }
        }
        return "\(limit.name) limit"
    }

    func isSlashCommandDisabled(_ command: AppServerSlashCommandDescriptor) -> Bool {
        command.requiresThread && self.selectedThreadID == nil
    }

    var menuWidth: CGFloat {
        304
    }

    var isDarkMode: Bool {
        self.colorScheme == .dark
    }

    var windowSafeAreaTopInset: CGFloat {
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

    func glassWhiteTint(light: Double, dark: Double) -> Color {
        Color.white.opacity(self.isDarkMode ? dark : light)
    }

    func accentGlassTint(light: Double, dark: Double) -> Color {
        Color.accentColor.opacity(self.isDarkMode ? dark : light)
    }

    var glassStrokeColor: Color {
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

}
