import Foundation
import SwiftUI
import Textual

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
            minHeight: self.commandPalettePanelMinHeight,
            maxHeight: self.commandPalettePanelMaxHeight,
            alignment: .top
        )
    }

    var commandPaletteTitle: String {
        if self.isReviewModePickerPresented {
            return "Code Review"
        }
        if self.pendingUserInputRequest != nil {
            return "Input Required"
        }
        return "Commands"
    }

    var pendingUserInputPanelBody: some View {
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

    func commandPaletteSubtitleLineLimit(for row: CommandPaletteRow) -> Int? {
        switch row {
        case .skill:
            return 1
        case .command, .mcp:
            return nil
        }
    }

    func isCommandPaletteRowDisabled(_ row: CommandPaletteRow) -> Bool {
        switch row {
        case .command(let command):
            return self.isSlashCommandDisabled(command)
        case .mcp, .skill:
            return false
        }
    }

    var chatComposer: some View {
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
    func composerTokenBadgeChip(_ badge: ComposerTokenBadge) -> some View {
        let icon = badge.kind == .mcp ? "shippingbox" : "sparkles"
        let background = badge.kind == .mcp ? Color.cyan.opacity(0.20) : Color.green.opacity(0.20)
        let border = badge.kind == .mcp ? Color.cyan.opacity(0.45) : Color.green.opacity(0.45)
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
