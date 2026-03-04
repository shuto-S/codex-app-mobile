import Foundation
import SwiftUI
import Textual
#if canImport(UIKit)
import UIKit
#endif

extension SessionWorkbenchView {
    func composerPickerChip(_ title: String, minWidth: CGFloat? = nil) -> some View {
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

    func composerIconChip(_ systemImage: String, minWidth: CGFloat = 48) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.92))
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
    func composerGitIconChip(minWidth: CGFloat = 48) -> some View {
        #if canImport(UIKit)
        if let gitMark = UIImage(named: "GitMark") {
            Image(uiImage: gitMark)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 18, height: 18)
                .frame(minWidth: minWidth, minHeight: 44, maxHeight: 44)
                .background {
                    self.glassCardBackground(cornerRadius: 22, tint: self.glassWhiteTint(light: 0.20, dark: 0.14))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(self.glassStrokeColor.opacity(0.56), lineWidth: 0.9)
                }
        } else {
            self.composerIconChip("arrow.triangle.branch", minWidth: minWidth)
        }
        #else
        self.composerIconChip("arrow.triangle.branch", minWidth: minWidth)
        #endif
    }

    @ViewBuilder
    var composerKeyboardDismissButton: some View {
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

    var composerControlBar: some View {
        let isGitMenuAvailable = self.selectedWorkspace != nil && !self.isRunningSSHAction && !self.isRunningGitAction
        return HStack(spacing: 8) {
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

            Menu {
                ForEach(GitMenuAction.allCases) { action in
                    Button {
                        self.handleGitMenuAction(action)
                    } label: {
                        Label(action.title, systemImage: action.systemImage)
                    }
                }
            } label: {
                self.composerGitIconChip(minWidth: 48)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Git Actions")
            .disabled(!isGitMenuAvailable)
            .opacity(isGitMenuAvailable ? 1 : 0.68)

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

    var commandPalettePanel: some View {
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
            } else if self.commandPaletteRows.isEmpty, !self.isCommandPaletteRefreshing {
                Text("No commands or skills available")
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
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    var commandPaletteSheet: some View {
        VStack(spacing: 0) {
            self.commandPalettePanel
                .padding(.horizontal, 12)
                .padding(.top, 12)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            Color.black
                .ignoresSafeArea()
        )
        .presentationDetents([.medium])
        .presentationContentInteraction(.scrolls)
        .presentationDragIndicator(.visible)
    }

    var statusSheet: some View {
        VStack(spacing: 0) {
            self.statusPanel
                .padding(.horizontal, 12)
                .padding(.top, 12)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            Color.black
                .ignoresSafeArea()
        )
        .presentationDetents([.medium, .large])
        .presentationContentInteraction(.scrolls)
        .presentationDragIndicator(.visible)
    }

    var mcpStatusSheet: some View {
        VStack(spacing: 0) {
            self.mcpStatusPanel
                .padding(.horizontal, 12)
                .padding(.top, 12)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            Color.black
                .ignoresSafeArea()
        )
        .presentationDetents([.medium, .large])
        .presentationContentInteraction(.scrolls)
        .presentationDragIndicator(.visible)
    }

    var reviewModePickerPanelBody: some View {
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
            maxHeight: self.commandPalettePanelMaxHeight,
            alignment: .top
        )
    }

    var commandPaletteTitle: String {
        if self.isReviewModePickerPresented {
            return "Code Review"
        }
        return "Commands"
    }

    func reviewModeOptionButton(
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

    var statusPanel: some View {
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
                    self.statusHeaderRow(label: "State", value: snapshot.connectionState.uppercased())
                    self.statusHeaderRow(label: "Model", value: snapshot.currentModel)
                    self.statusHeaderRow(
                        label: "Plan",
                        value: snapshot.planType?.uppercased() ?? "Unknown"
                    )
                    self.statusHeaderRow(
                        label: "Reconnects",
                        value: "\(snapshot.reconnectAttemptCount)"
                    )
                    if let lastSuccessfulPingAt = snapshot.lastSuccessfulPingAt {
                        self.statusHeaderRow(
                            label: "Last ping",
                            value: lastSuccessfulPingAt.formatted(date: .omitted, time: .shortened)
                        )
                    }
                    if let lastRPCErrorMessage = snapshot.lastRPCErrorMessage {
                        let timestampSuffix = snapshot.lastRPCErrorAt.map {
                            " (\($0.formatted(date: .omitted, time: .shortened)))"
                        } ?? ""
                        Text("RPC error: \(lastRPCErrorMessage)\(timestampSuffix)")
                            .font(.caption2)
                            .foregroundStyle(Color.orange.opacity(0.90))
                    }
                    if let modelUpgradeNotice = snapshot.modelUpgradeNotice,
                       !modelUpgradeNotice.isEmpty {
                        Text(modelUpgradeNotice)
                            .font(.caption)
                            .foregroundStyle(Color.yellow.opacity(0.92))
                    }
                    if let modelAvailabilityNotice = snapshot.modelAvailabilityNotice,
                       !modelAvailabilityNotice.isEmpty {
                        Text(modelAvailabilityNotice)
                            .font(.caption)
                            .foregroundStyle(Color.orange.opacity(0.90))
                    }
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

    var mcpStatusPanel: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Text("MCP Status")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.white)

                Spacer(minLength: 8)

                if self.isMCPStatusRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.white.opacity(0.9))
                }

                Button("Refresh") {
                    self.refreshMCPStatusSheet()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.92))

                Button("Close") {
                    self.dismissMCPStatusSheet()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.92))
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            Text(self.mcpStatusHeadline)
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.88))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
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

    var gitOperationSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text(self.gitModalActionSelection.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.94))
                    .frame(maxWidth: .infinity, alignment: .leading)

                if self.gitModalActionSelection.requiresCommitMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Commit message (optional)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.72))

                        TextField(
                            "Leave empty to generate with AI",
                            text: self.$gitCommitMessageDraft,
                            axis: .vertical
                        )
                        .lineLimit(1...3)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .foregroundStyle(Color.white)
                        .tint(Color.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
                        )
                        .disabled(self.isRunningGitAction)
                    }
                } else {
                    Text("Push current branch. If upstream is not configured, it will be set to origin automatically.")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.72))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !self.gitOperationFeedback.isEmpty {
                    Label(self.gitOperationFeedback, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.green.opacity(0.92))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !self.gitOperationErrorMessage.isEmpty {
                    Text(self.gitOperationErrorMessage)
                        .font(.caption)
                        .foregroundStyle(Color.red.opacity(0.92))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 0)

                Button {
                    self.executeGitModalAction()
                } label: {
                    HStack(spacing: 8) {
                        if self.isRunningGitAction {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(self.gitModalActionSelection.actionButtonTitle)
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(self.isRunningGitAction)
                .opacity(self.isRunningGitAction ? 0.68 : 1)
            }
            .padding(16)
            .navigationTitle(self.gitModalActionSelection.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        if !self.isRunningGitAction {
                            self.activeGitOperationSheet = nil
                        }
                    }
                    .disabled(self.isRunningGitAction)
                }
            }
            .background(Color.black.ignoresSafeArea())
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    var gitDiffPage: some View {
        Group {
            switch self.gitDiffLoadState {
            case .idle, .loading:
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(Color.white.opacity(0.92))
                    Text("Loading diff...")
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.78))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                VStack(spacing: 14) {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(Color.red.opacity(0.92))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: 360, alignment: .leading)

                    Button("Retry") {
                        self.reloadGitDiffPage()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white, in: Capsule())
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 16)
            case .loaded(let snapshot):
                VStack(spacing: 0) {
                    self.gitDiffSummaryHeader(snapshot.summary)

                    if snapshot.files.isEmpty {
                        Text("No textual diff to display.")
                            .font(.subheadline)
                            .foregroundStyle(Color.white.opacity(0.72))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            .padding(.horizontal, 16)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(snapshot.files) { file in
                                    self.gitDiffFileCard(file)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                        }
                    }
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(self.gitDiffNavigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        self.reloadGitDiffPage()
                    } label: {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }

                    Divider()

                    Button {
                        self.presentGitOperationSheet(initialAction: .commit)
                    } label: {
                        Label("Commit", systemImage: "checkmark.circle")
                    }

                    Button {
                        self.presentGitOperationSheet(initialAction: .commitAndPush)
                    } label: {
                        Label("Commit+Push", systemImage: "arrow.up.doc")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(self.gitDiffLoadState == .loading || self.isRunningGitAction)
            }
        }
    }

    var gitDiffNavigationTitle: String {
        if case .loaded(let snapshot) = self.gitDiffLoadState {
            return snapshot.summary.branchName
        }
        return "Diff"
    }

    func gitDiffSummaryHeader(_ summary: GitDiffSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let additions = summary.additions,
               let deletions = summary.deletions {
                HStack(spacing: 8) {
                    Text("+\(self.groupedTokenCount(additions))")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Color.green.opacity(0.98))
                    Text("-\(self.groupedTokenCount(deletions))")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Color.red.opacity(0.98))
                }
            } else {
                Text("\(summary.changedFiles) files changed")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.94))
            }

            if summary.untrackedFiles > 0 {
                Text("\(summary.untrackedFiles) untracked file\(summary.untrackedFiles == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.62))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.06))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 0.7)
        }
    }

    func gitDiffFileCard(_ file: GitDiffFile) -> some View {
        let totals = self.gitDiffFileLineTotals(file)
        let isExpanded = self.gitDiffExpandedFileIDs.contains(file.id)
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    self.toggleGitDiffFileExpansion(file.id)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.78))

                    Text(file.displayPath)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.94))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("+\(self.groupedTokenCount(totals.additions))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.green.opacity(0.98))

                    Text("-\(self.groupedTokenCount(totals.deletions))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.red.opacity(0.98))
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(file.hunks) { hunk in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(hunk.header)
                            .font(.caption2.monospaced())
                            .foregroundStyle(Color.white.opacity(0.72))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.06))

                        ForEach(hunk.lines) { line in
                            self.gitDiffLineRow(line)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.7)
                    )
                }
                if file.hunks.isEmpty {
                    Text("No textual hunks.")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.62))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
        )
    }

    func gitDiffFileLineTotals(_ file: GitDiffFile) -> (additions: Int, deletions: Int) {
        var additions = 0
        var deletions = 0
        for hunk in file.hunks {
            for line in hunk.lines {
                switch line.kind {
                case .addition:
                    additions += 1
                case .deletion:
                    deletions += 1
                case .context, .meta:
                    break
                }
            }
        }
        return (additions, deletions)
    }

    func toggleGitDiffFileExpansion(_ fileID: String) {
        if self.gitDiffExpandedFileIDs.contains(fileID) {
            self.gitDiffExpandedFileIDs.remove(fileID)
        } else {
            self.gitDiffExpandedFileIDs.insert(fileID)
        }
    }

    func gitDiffLineRow(_ line: GitDiffLine) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(line.oldLineNumber.map(String.init) ?? "")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.46))
                .frame(width: 42, alignment: .trailing)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)

            Text(line.newLineNumber.map(String.init) ?? "")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.46))
                .frame(width: 42, alignment: .trailing)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)

            Text(verbatim: self.gitDiffLineBodyText(line))
                .font(.caption.monospaced())
                .foregroundStyle(Color.white.opacity(0.92))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .textSelection(.enabled)
        }
        .background(self.gitDiffLineBackground(line.kind))
    }

    func gitDiffLineBodyText(_ line: GitDiffLine) -> String {
        switch line.kind {
        case .addition:
            return "+" + line.text
        case .deletion:
            return "-" + line.text
        case .context:
            return " " + line.text
        case .meta:
            return line.text
        }
    }

    func gitDiffLineBackground(_ kind: GitDiffLineKind) -> Color {
        switch kind {
        case .addition:
            return Color.green.opacity(0.16)
        case .deletion:
            return Color.red.opacity(0.16)
        case .context:
            return Color.clear
        case .meta:
            return Color.white.opacity(0.06)
        }
    }

    @ViewBuilder
    func statusHeaderRow(label: String, value: String) -> some View {
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
    func statusLimitRow(_ limit: StatusLimitBarSnapshot) -> some View {
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

    func statusContextSummary(_ snapshot: StatusPanelSnapshot) -> String {
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

    func statusLimitRemainingText(_ limit: StatusLimitBarSnapshot) -> String {
        guard let remainingPercent = limit.remainingPercent else {
            return "unknown"
        }
        return "\(Int(remainingPercent.rounded()))% left"
    }

    func statusLimitResetText(_ resetAt: Date?) -> String? {
        guard let resetAt else { return nil }
        if Calendar.current.isDate(resetAt, inSameDayAs: Date()) {
            return resetAt.formatted(date: .omitted, time: .shortened)
        }
        return resetAt.formatted(Date.FormatStyle().month().day())
    }

    func statusLimitFillFraction(_ remainingPercent: Double?) -> CGFloat {
        guard let remainingPercent else {
            return 0
        }
        let normalized = max(0, min(100, remainingPercent)) / 100
        return CGFloat(normalized)
    }

    func groupedTokenCount(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    func compactTokenCount(_ value: Int) -> String {
        let absolute = abs(value)
        if absolute >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if absolute >= 1_000 {
            return String(format: "%.0fK", Double(value) / 1_000)
        }
        return value.formatted()
    }

    func commandPaletteRowButton(_ row: CommandPaletteRow) -> some View {
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

    func commandPaletteMetadata(for row: CommandPaletteRow) -> (title: String, subtitle: String?, systemImage: String) {
        switch row {
        case .command(let command):
            return (command.title, command.description, command.systemImage)
        case .skill(let skill):
            let description = skill.description?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (
                skill.name,
                (description?.isEmpty == false) ? description : "Skill",
                "sparkles"
            )
        }
    }

    func commandPaletteSubtitleLineLimit(for row: CommandPaletteRow) -> Int? {
        switch row {
        case .skill:
            return 1
        case .command:
            return nil
        }
    }

    func isCommandPaletteRowDisabled(_ row: CommandPaletteRow) -> Bool {
        switch row {
        case .command(let command):
            return self.isSlashCommandDisabled(command)
        case .skill:
            return false
        }
    }

    var chatComposer: some View {
        let isInactive = !self.isComposerInteractive
        let isInterruptButton = self.isPromptEmpty && self.canInterruptActiveTurn
        let isPrimaryActionEnabled = isInterruptButton ? self.canInterruptActiveTurn : self.canSendPrompt

        return VStack(alignment: .leading, spacing: 8) {
            self.composerControlBar

            if let descriptor = self.selectedComposerModelDescriptor {
                if let upgradeInfo = descriptor.upgradeInfo {
                    Text(upgradeInfo.upgradeCopy ?? "Upgrade available: \(upgradeInfo.model)")
                        .font(.caption2)
                        .foregroundStyle(Color.yellow.opacity(0.92))
                        .padding(.horizontal, 4)
                }
                if let availabilityNuxMessage = descriptor.availabilityNuxMessage,
                   !availabilityNuxMessage.isEmpty {
                    Text(availabilityNuxMessage)
                        .font(.caption2)
                        .foregroundStyle(Color.orange.opacity(0.90))
                        .padding(.horizontal, 4)
                }
            }

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
                        if isInterruptButton {
                            self.interruptActiveTurn()
                        } else {
                            self.sendPrompt(forceNewThread: false)
                        }
                    } label: {
                        Image(systemName: isInterruptButton ? "square.fill" : "arrow.up")
                            .font(.system(size: isInterruptButton ? 11 : 15, weight: .bold))
                            .foregroundStyle(isInactive ? Color.white.opacity(0.72) : Color.black)
                            .frame(width: 36, height: 36)
                            .background((isInactive ? Color.white.opacity(0.24) : Color.white), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!isPrimaryActionEnabled)
                    .opacity(isPrimaryActionEnabled ? 1 : 0.45)
                    .accessibilityLabel(isInterruptButton ? "Stop inference" : "Send prompt")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                self.glassCardBackground(
                    cornerRadius: 24,
                    tint: self.glassWhiteTint(
                        light: isInactive ? 0.20 : 0.16,
                        dark: isInactive ? 0.12 : 0.08
                    )
                )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(self.glassStrokeColor.opacity(isInactive ? 0.62 : 0.46), lineWidth: 1)
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
        .background(Color.clear)
    }
    func composerTokenBadgeChip(_ badge: ComposerTokenBadge) -> some View {
        let icon = "sparkles"
        let background = Color.green.opacity(0.20)
        let border = Color.green.opacity(0.45)
        return Button {
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

    func removeComposerTokenBadge(_ badge: ComposerTokenBadge) {
        self.selectedComposerTokenBadges.removeAll { $0.id == badge.id }
    }

}
