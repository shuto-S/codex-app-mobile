import Foundation
import SwiftUI
import Textual

extension SessionWorkbenchView {
    var chatBackground: some View {
        Color.black
    }

    var chatHeader: some View {
        HStack(spacing: 12) {
            Button {
                self.isPromptFieldFocused = false
                self.isCommandPalettePresented = false
                self.isStatusPanelPresented = false
                self.isMCPStatusSheetPresented = false
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
                    .disabled(selectedThreadSummary.ephemeral)
                    if selectedThreadSummary.ephemeral {
                        Text("Ephemeral threads cannot be archived")
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

    var chatHeaderArea: some View {
        VStack(spacing: 0) {
            self.chatHeader
        }
        .background(Color.black)
    }

    var floatingBannerCount: Int {
        var count = 0
        if self.shouldShowPendingApprovalsBanner { count += 1 }
        if self.composerInfoMessage != nil { count += 1 }
        return count
    }

    var shouldShowPendingApprovalsBanner: Bool {
        !self.isSSHTransport && !self.appState.appServerClient.pendingRequests.isEmpty
    }

    var floatingBannerTopInset: CGFloat {
        guard self.floatingBannerCount > 0 else { return 16 }
        let rows = CGFloat(self.floatingBannerCount)
        let rowHeight: CGFloat = 44
        let rowSpacing: CGFloat = 8
        return 16 + (rows * rowHeight) + (max(0, rows - 1) * rowSpacing) + 10
    }

    var chatTimeline: some View {
        ScrollViewReader { proxy in
            let composerBottomInset = max(18, self.effectiveChatComposerOverlayHeight + 18)
            ScrollView {
                VStack(spacing: 14) {
                    if self.workspaces.isEmpty {
                        self.chatCreateProjectCallToAction
                    } else if self.selectedWorkspace == nil {
                        self.chatPlaceholder("Select a project.")
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
                        .frame(height: composerBottomInset)
                        .id("chat-bottom")
                }
                .padding(.horizontal, 18)
                .padding(.top, self.floatingBannerTopInset)
            }
            .background(Color.black)
            .scrollDismissesKeyboard(.interactively)
            .onScrollGeometryChange(for: ChatScrollSnapshot.self) { geometry in
                self.chatScrollSnapshot(from: geometry)
            } action: { _, newValue in
                let previousSnapshot = self.lastChatScrollSnapshot
                self.chatDistanceFromBottom = newValue.distanceFromBottom
                self.lastChatScrollSnapshot = newValue

                guard self.selectedThreadID != nil else {
                    self.isChatAutoFollowEnabled = true
                    return
                }

                self.isChatAutoFollowEnabled = Self.nextAutoFollowState(
                    previous: previousSnapshot,
                    current: newValue,
                    wasEnabled: self.isChatAutoFollowEnabled
                )
            }
            .overlay(alignment: .bottom) {
                if self.shouldShowScrollToBottomButton {
                    self.scrollToBottomButton(proxy: proxy)
                        .padding(.bottom, max(12, self.effectiveChatComposerOverlayHeight + 12))
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .overlay(alignment: .top) {
                if self.floatingBannerCount > 0 {
                    VStack(spacing: 8) {
                        if self.shouldShowPendingApprovalsBanner {
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
                                .background(
                                    Color.orange.opacity(0.18),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        if let composerInfoMessage {
                            self.floatingChatInfoBanner(
                                text: composerInfoMessage.text,
                                tone: composerInfoMessage.tone
                            )
                            .allowsHitTesting(false)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.easeOut(duration: 0.18), value: self.shouldShowScrollToBottomButton)
            .onAppear {
                self.isChatAutoFollowEnabled = true
                self.lastChatScrollSnapshot = nil
                self.shouldForceScrollToBottomOnNextTranscriptUpdate = true
                self.scrollToBottom(proxy: proxy)
            }
            .onChange(of: self.scrollToBottomRequestCount) {
                self.isChatAutoFollowEnabled = true
                self.scrollToBottom(proxy: proxy)
            }
            .onChange(of: self.selectedThreadID) {
                self.isChatAutoFollowEnabled = true
                self.lastChatScrollSnapshot = nil
                self.shouldForceScrollToBottomOnNextTranscriptUpdate = true
                self.scrollToBottom(proxy: proxy)
            }
            .onChange(of: self.selectedThreadTranscript) {
                if self.shouldForceScrollToBottomOnNextTranscriptUpdate {
                    self.isChatAutoFollowEnabled = true
                    self.shouldForceScrollToBottomOnNextTranscriptUpdate = false
                    self.scrollToBottom(proxy: proxy)
                    return
                }
                guard self.shouldAutoFollowChatUpdates else { return }
                self.scrollToBottom(proxy: proxy)
            }
            .onChange(of: self.parsedChatMessages.count) {
                if self.shouldForceScrollToBottomOnNextTranscriptUpdate {
                    self.isChatAutoFollowEnabled = true
                    self.shouldForceScrollToBottomOnNextTranscriptUpdate = false
                    self.scrollToBottom(proxy: proxy)
                    return
                }
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
    func scrollToBottomButton(proxy: ScrollViewProxy) -> some View {
        Button {
            self.isChatAutoFollowEnabled = true
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
    func chatInfoBanner(
        text: String,
        tone: InfoBannerTone
    ) -> some View {
        let style = self.infoBannerStyle(for: tone)
        return Label(text, systemImage: style.icon)
            .font(.caption)
            .foregroundStyle(style.foreground)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(style.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    func floatingChatInfoBanner(
        text: String,
        tone: InfoBannerTone
    ) -> some View {
        let style = self.infoBannerStyle(for: tone)

        Label(text, systemImage: style.icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(style.foreground)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                self.glassCardBackground(
                    cornerRadius: 14,
                    tint: self.floatingBannerTint(for: tone)
                )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(self.glassStrokeColor.opacity(0.58), lineWidth: 0.9)
            }
            .shadow(color: .black.opacity(self.isDarkMode ? 0.28 : 0.16), radius: 12, x: 0, y: 4)
    }

    func floatingBannerTint(for tone: InfoBannerTone) -> Color {
        switch tone {
        case .status:
            return self.glassWhiteTint(light: 0.18, dark: 0.12)
        case .success:
            return Color.green.opacity(self.isDarkMode ? 0.22 : 0.16)
        case .error:
            return Color.red.opacity(self.isDarkMode ? 0.22 : 0.16)
        }
    }

    func infoBannerStyle(for tone: InfoBannerTone) -> (icon: String, foreground: Color, background: Color) {
        switch tone {
        case .status:
            return ("checkmark.circle", Color.white.opacity(0.78), Color.white.opacity(0.08))
        case .success:
            return ("checkmark.circle.fill", Color.white.opacity(0.88), Color.green.opacity(0.18))
        case .error:
            return ("exclamationmark.triangle.fill", .red, Color.red.opacity(0.12))
        }
    }

    func chatStreamingStatusRow(baseText: String) -> some View {
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

    var chatCreateProjectCallToAction: some View {
        VStack(spacing: 14) {
            Text("No projects yet.")
                .font(.headline)
                .foregroundStyle(Color.white.opacity(0.88))

            Button {
                self.isPromptFieldFocused = false
                self.editingWorkspace = nil
                self.isPresentingProjectEditor = true
                self.isMenuOpen = false
            } label: {
                Label("Create Project", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background {
                        self.glassCardBackground(
                            cornerRadius: 14,
                            tint: self.accentGlassTint(light: 0.18, dark: 0.14)
                        )
                    }
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .center)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    func chatPlaceholder(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Color.white.opacity(0.62))
            .frame(maxWidth: .infinity, minHeight: 200, alignment: .center)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    func chatMessageRow(_ message: SessionChatMessage) -> some View {
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
    func assistantMarkdownView(
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

    func normalizedMarkdown(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
    }
}
