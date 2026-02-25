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
                    let message = self.userFacingSSHError(error)
                    self.localStatusMessage = ""
                    self.localErrorMessage = message
                    self.showComposerInfo(message, tone: .error, autoDismissAfter: 4.0)
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

}
