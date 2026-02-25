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

    var chatHeaderArea: some View {
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

    var chatTimeline: some View {
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
    func scrollToBottomButton(proxy: ScrollViewProxy) -> some View {
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
