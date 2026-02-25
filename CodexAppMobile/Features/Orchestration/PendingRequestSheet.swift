import SwiftUI

struct PendingRequestSheet: View {
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
                case .commandApproval(let command, let cwd, let reason):
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

                    Section("Decision") {
                        ForEach(AppServerCommandApprovalDecision.allCases) { decision in
                            Button(decision.rawValue) {
                                self.respondCommand(decision)
                            }
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

    private func respondCommand(_ decision: AppServerCommandApprovalDecision) {
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
