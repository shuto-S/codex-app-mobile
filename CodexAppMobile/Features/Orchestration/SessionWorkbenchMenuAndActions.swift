import Foundation
import SwiftUI
import Textual

extension SessionWorkbenchView {
    var sideMenu: some View {
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

    var menuEdgeOpenHandle: some View {
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
    func glassCardBackground(cornerRadius: CGFloat, tint: Color? = nil) -> some View {
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
    func glassCircleBackground(size: CGFloat, tint: Color? = nil) -> some View {
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

    func scrollToBottom(proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo("chat-bottom", anchor: .bottom)
            }
        }
    }

    func distanceToChatBottom(from geometry: ScrollGeometry) -> CGFloat {
        let visibleBottomY = geometry.contentOffset.y + geometry.containerSize.height
        let distance = geometry.contentSize.height - visibleBottomY
        return max(0, distance)
    }

    func selectWorkspace(_ workspace: ProjectWorkspace) {
        let previousWorkspaceID = self.selectedWorkspaceID
        self.selectedWorkspaceID = workspace.id
        if previousWorkspaceID != workspace.id {
            self.selectedThreadID = nil
            self.appState.hostSessionStore.selectThread(hostID: self.host.id, threadID: nil)
        }
        self.appState.hostSessionStore.selectProject(hostID: self.host.id, projectID: workspace.id)
        self.refreshThreads()
    }

    func selectThread(_ summary: CodexThreadSummary, workspaceID: UUID) {
        self.selectedWorkspaceID = workspaceID
        self.selectedThreadID = summary.threadID
        self.appState.hostSessionStore.selectProject(hostID: self.host.id, projectID: workspaceID)
        self.appState.hostSessionStore.selectThread(hostID: self.host.id, threadID: summary.threadID)
        self.applyComposerSelection(model: summary.model, reasoningEffort: summary.reasoningEffort)
        self.loadThread(summary.threadID)
        self.isMenuOpen = false
    }

    func createNewThread() {
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

    func deleteWorkspace(_ workspace: ProjectWorkspace) {
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

    func syncComposerControlsWithWorkspace() {
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

    func syncComposerReasoningWithModel() {
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

    func applyComposerSelection(model: String?, reasoningEffort: String?) {
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

    func updateThreadBookmarkSettings(threadID: String, model: String?, reasoningEffort: String?) {
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

    static func parseChatMessages(from transcript: String) -> [SessionChatMessage] {
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

    static func progressDetailContent(from line: String) -> String {
        guard let colonIndex = line.firstIndex(of: ":") else {
            return line
        }
        var content = line[line.index(after: colonIndex)...]
        if content.first == " " {
            content = content.dropFirst()
        }
        return String(content)
    }

    func restoreSelectionFromSession() {
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

    func connectHost() {
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

    func disconnectHost() {
        if self.isSSHTransport {
            return
        }
        self.appState.appServerClient.disconnect()
    }

    func refreshThreads() {
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

    func sendPrompt(forceNewThread: Bool) {
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

    func presentCommandPalette() {
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

    func dismissCommandPalette() {
        self.isCommandPalettePresented = false
        self.dismissReviewModePicker()
        self.dismissPendingUserInputPanel()
    }

    func presentReviewModePicker() {
        guard self.isCommandPalettePresented else {
            self.localErrorMessage = "Open commands and select /review again."
            return
        }
        self.dismissPendingUserInputPanel()
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

    func dismissPendingUserInputPanel() {
        self.pendingUserInputRequest = nil
        self.pendingUserInputAnswers = [:]
        self.pendingUserInputSubmitError = ""
        self.isSubmittingPendingUserInput = false
    }

    func handlePendingRequestsUpdated() {
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

    func presentFirstPendingRequest() {
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

    func submitPendingUserInputAnswers() {
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

    func handleCommandPaletteBackAction() {
        if self.isReviewModePickerPresented {
            self.dismissReviewModePicker()
            return
        }
        if self.pendingUserInputRequest != nil {
            self.dismissPendingUserInputPanel()
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
                self.localErrorMessage = self.appState.appServerClient.userFacingMessage(for: error)
            }
        }
    }

    func presentStatusPanel() {
        guard !self.isSSHTransport else {
            self.localErrorMessage = "Slash commands are only available in App Server mode."
            return
        }
        self.dismissCommandPalette()
        self.isStatusPanelPresented = true
        self.statusSnapshot = self.makeStatusSnapshot()
        self.refreshStatusPanel()
    }

    func dismissStatusPanel() {
        self.isStatusPanelPresented = false
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
                self.localErrorMessage = self.appState.appServerClient.userFacingMessage(for: error)
            }
        }
    }

    func showComposerInfo(
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

    func clearComposerInfo() {
        self.composerInfoDismissTask?.cancel()
        self.composerInfoDismissTask = nil
        self.composerInfoMessage = nil
    }

    func handleCommandPaletteSelection(_ row: CommandPaletteRow) {
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

    func executeSlashCommand(_ command: AppServerSlashCommandDescriptor) {
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

    func refreshAppServerCatalogsForCurrentWorkspace() {
        guard !self.isSSHTransport else { return }
        Task {
            await self.appState.appServerClient.refreshCatalogs(primaryCWD: self.selectedWorkspace?.remotePath)
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

    func startReviewAgainstBaseBranch() {
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

    func startReviewForCurrentThread(
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

    func showStatusSlashCommand() {
        self.presentStatusPanel()
    }

    func startPlanModeSlashCommand() {
        self.composerCollaborationModeID = self.planCollaborationModeID
        self.shouldPresentNextUserInputPanelAfterPlan = true
        self.showComposerInfo("Plan mode enabled. Send a prompt to continue.", tone: .status)
        self.isPromptFieldFocused = true
    }

    func disablePlanMode() {
        guard self.composerCollaborationModeIDForRequest != nil else { return }
        self.composerCollaborationModeID = ""
        self.shouldPresentNextUserInputPanelAfterPlan = false
        self.showComposerInfo("Plan mode disabled.", tone: .status)
    }

    func consumePlanModeAfterSend() {
        guard self.isPlanModeEnabled else { return }
        // Keep pending user-input auto-presentation armed for the already-started plan turn.
        self.composerCollaborationModeID = ""
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
                self.localStatusMessage = "Executed via codex exec over SSH."
            } catch {
                self.localErrorMessage = self.userFacingSSHError(error)
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
                    model: resolvedModel,
                    reasoningEffort: resolvedReasoning
                )
            } catch {
                self.localErrorMessage = self.appState.appServerClient.userFacingMessage(for: error)
            }
        }
    }

    func interruptActiveTurn() {
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

    func archiveThread(summary: CodexThreadSummary, archived: Bool) {
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
