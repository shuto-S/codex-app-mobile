import SwiftUI

struct PendingRequestSheet: View {
    private struct CommandDecisionRow: Identifiable {
        let id: String
        let title: String
        let decision: AppServerCommandApprovalDecisionResponse?
    }

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let request: AppServerPendingRequest

    @State private var freeFormAnswers: [String: String] = [:]
    @State private var submitError = ""

    init(request: AppServerPendingRequest) {
        self.request = request

        var defaults: [String: String] = [:]
        if case .userInput(let questions) = request.kind {
            for question in questions {
                defaults[question.id] = question.options.first?.label ?? ""
            }
        }
        _freeFormAnswers = State(initialValue: defaults)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Method") {
                    Text(self.request.method)
                        .font(.footnote)
                        .textSelection(.enabled)
                    if !self.request.threadID.isEmpty {
                        Text("thread: \(self.request.threadID)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !self.request.turnID.isEmpty {
                        Text("turn: \(self.request.turnID)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                switch self.request.kind {
                case .commandApproval(
                    let command,
                    let cwd,
                    let reason,
                    let availableDecisions,
                    let proposedExecPolicyAmendment,
                    let proposedNetworkPolicyAmendments,
                    let networkApprovalContext,
                    let additionalPermissions
                ):
                    Section("Command") {
                        Text(command.isEmpty ? "(empty command)" : command)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)

                        if let cwd,
                           !cwd.isEmpty {
                            Text("cwd: \(cwd)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let reason,
                           !reason.isEmpty {
                            Text(reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let additionalPermissions {
                        Section("Requested Access") {
                            if let network = additionalPermissions.network {
                                Text("Network: \(network ? "required" : "not required")")
                                    .font(.caption)
                            }
                            if let fileSystem = additionalPermissions.fileSystem {
                                let readable = fileSystem.read?.count ?? 0
                                let writable = fileSystem.write?.count ?? 0
                                Text("File system: read \(readable) path(s), write \(writable) path(s)")
                                    .font(.caption)
                            }
                        }
                    }

                    if let proposedExecPolicyAmendment,
                       !proposedExecPolicyAmendment.command.isEmpty {
                        Section("Exec Policy Proposal") {
                            Text(proposedExecPolicyAmendment.command.joined(separator: " "))
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }

                    if !proposedNetworkPolicyAmendments.isEmpty || networkApprovalContext != nil {
                        Section("Network Policy") {
                            if let networkApprovalContext {
                                let protocolValue = networkApprovalContext.protocol?.uppercased() ?? "UNKNOWN"
                                Text("Host: \(networkApprovalContext.host) (\(protocolValue))")
                                    .font(.caption)
                            }
                            ForEach(proposedNetworkPolicyAmendments.indices, id: \.self) { index in
                                let amendment = proposedNetworkPolicyAmendments[index]
                                Text("\(amendment.action.rawValue.uppercased()): \(amendment.host)")
                                    .font(.caption)
                            }
                        }
                    }

                    Section("Decision") {
                        ForEach(self.commandDecisionRows(
                            availableDecisions: availableDecisions,
                            proposedExecPolicyAmendment: proposedExecPolicyAmendment,
                            proposedNetworkPolicyAmendments: proposedNetworkPolicyAmendments,
                            networkApprovalContext: networkApprovalContext
                        )) { row in
                            Button(row.title) {
                                guard let decision = row.decision else { return }
                                self.respondCommand(decision)
                            }
                            .disabled(row.decision == nil)
                        }
                    }

                case .fileChange(let reason):
                    Section("File Change") {
                        if let reason,
                           !reason.isEmpty {
                            Text(reason)
                                .font(.footnote)
                        } else {
                            Text("Codex requests file-change approval.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("Decision") {
                        ForEach(AppServerFileApprovalDecision.allCases) { decision in
                            Button(decision.rawValue) {
                                self.respondFileChange(decision)
                            }
                        }
                    }

                case .userInput(let questions):
                    ForEach(questions) { question in
                        Section(question.prompt) {
                            if !question.options.isEmpty {
                                ForEach(question.options.indices, id: \.self) { index in
                                    let option = question.options[index]
                                    Button {
                                        self.freeFormAnswers[question.id] = option.label
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(option.label)
                                            if !option.description.isEmpty {
                                                Text(option.description)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                            }

                            TextField("Answer", text: Binding(
                                get: { self.freeFormAnswers[question.id] ?? "" },
                                set: { self.freeFormAnswers[question.id] = $0 }
                            ))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                        }
                    }

                    Section {
                        Button("Submit") {
                            self.respondUserInput(questions: questions)
                        }
                    }

                case .unknown:
                    Section {
                        Text("This request type is not yet mapped. Reply from desktop fallback if needed.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if !self.submitError.isEmpty {
                    Section {
                        Text(self.submitError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(self.request.title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        self.dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                    .codexActionButtonStyle()
                }
            }
        }
    }

    private func commandDecisionRows(
        availableDecisions: [AppServerCommandApprovalDecisionOption],
        proposedExecPolicyAmendment: AppServerExecPolicyAmendment?,
        proposedNetworkPolicyAmendments: [AppServerNetworkPolicyAmendment],
        networkApprovalContext: AppServerNetworkApprovalContext?
    ) -> [CommandDecisionRow] {
        let sourceDecisions: [AppServerCommandApprovalDecisionOption]
        if availableDecisions.isEmpty {
            sourceDecisions = [.accept, .acceptForSession, .decline, .cancel]
        } else {
            sourceDecisions = availableDecisions
        }

        var rows: [CommandDecisionRow] = []
        var counter = 0
        func nextID(_ prefix: String) -> String {
            defer { counter += 1 }
            return "\(prefix)-\(counter)"
        }

        for decision in sourceDecisions {
            switch decision {
            case .accept:
                rows.append(CommandDecisionRow(
                    id: nextID("accept"),
                    title: "Accept",
                    decision: .accept
                ))
            case .acceptForSession:
                rows.append(CommandDecisionRow(
                    id: nextID("accept-session"),
                    title: "Accept for Session",
                    decision: .acceptForSession
                ))
            case .decline:
                rows.append(CommandDecisionRow(
                    id: nextID("decline"),
                    title: "Decline",
                    decision: .decline
                ))
            case .cancel:
                rows.append(CommandDecisionRow(
                    id: nextID("cancel"),
                    title: "Cancel Turn",
                    decision: .cancel
                ))
            case .acceptWithExecpolicyAmendment(let amendment):
                if let amendment = amendment ?? proposedExecPolicyAmendment {
                    rows.append(CommandDecisionRow(
                        id: nextID("accept-execpolicy"),
                        title: "Accept + Save Exec Policy",
                        decision: .acceptWithExecpolicyAmendment(amendment: amendment)
                    ))
                } else {
                    rows.append(CommandDecisionRow(
                        id: nextID("accept-execpolicy-missing"),
                        title: "Accept + Save Exec Policy (Unavailable)",
                        decision: nil
                    ))
                }
            case .applyNetworkPolicyAmendment(let amendment):
                if let amendment = amendment ?? proposedNetworkPolicyAmendments.first {
                    rows.append(CommandDecisionRow(
                        id: nextID("network-policy"),
                        title: "Apply Network Policy: \(amendment.action.rawValue.uppercased()) \(amendment.host)",
                        decision: .applyNetworkPolicyAmendment(amendment: amendment)
                    ))
                } else if let networkApprovalContext {
                    rows.append(CommandDecisionRow(
                        id: nextID("network-allow"),
                        title: "Allow host \(networkApprovalContext.host)",
                        decision: .applyNetworkPolicyAmendment(
                            amendment: AppServerNetworkPolicyAmendment(
                                host: networkApprovalContext.host,
                                action: .allow
                            )
                        )
                    ))
                    rows.append(CommandDecisionRow(
                        id: nextID("network-deny"),
                        title: "Deny host \(networkApprovalContext.host)",
                        decision: .applyNetworkPolicyAmendment(
                            amendment: AppServerNetworkPolicyAmendment(
                                host: networkApprovalContext.host,
                                action: .deny
                            )
                        )
                    ))
                } else {
                    rows.append(CommandDecisionRow(
                        id: nextID("network-policy-missing"),
                        title: "Apply Network Policy (Unavailable)",
                        decision: nil
                    ))
                }
            }
        }

        return rows
    }

    private func respondCommand(_ decision: AppServerCommandApprovalDecisionResponse) {
        self.submitError = ""
        Task {
            do {
                try await self.appState.appServerClient.respondCommandApproval(request: self.request, decision: decision)
                self.dismiss()
            } catch {
                self.submitError = self.appState.appServerClient.userFacingMessage(for: error)
            }
        }
    }

    private func respondFileChange(_ decision: AppServerFileApprovalDecision) {
        self.submitError = ""
        Task {
            do {
                try await self.appState.appServerClient.respondFileChangeApproval(request: self.request, decision: decision)
                self.dismiss()
            } catch {
                self.submitError = self.appState.appServerClient.userFacingMessage(for: error)
            }
        }
    }

    private func respondUserInput(questions: [AppServerUserInputQuestion]) {
        self.submitError = ""

        var answers: [String: [String]] = [:]
        for question in questions {
            let raw = self.freeFormAnswers[question.id, default: ""]
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
            do {
                try await self.appState.appServerClient.respondUserInput(request: self.request, answers: answers)
                self.dismiss()
            } catch {
                self.submitError = self.appState.appServerClient.userFacingMessage(for: error)
            }
        }
    }
}
