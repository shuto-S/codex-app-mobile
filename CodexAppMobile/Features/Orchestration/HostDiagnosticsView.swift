import SwiftUI

struct HostDiagnosticsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var errorMessage = ""

    private var diagnostics: AppServerDiagnostics {
        self.appState.appServerClient.diagnostics
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.text("Host")) {
                    Text(L10n.format("State: %@", self.appState.appServerClient.state.rawValue))
                    Text(L10n.format("Session state: %@", self.diagnostics.connectionState))
                    if !self.appState.appServerClient.connectedEndpoint.isEmpty {
                        Text(self.appState.appServerClient.connectedEndpoint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                Section(L10n.text("Codex CLI")) {
                    Text(L10n.format(
                        "CLI version: %@",
                        self.diagnostics.cliVersion.isEmpty ? L10n.text("unknown") : self.diagnostics.cliVersion
                    ))
                    Text(L10n.format("Required >= %@", self.diagnostics.minimumRequiredVersion))
                    Text(L10n.format("Auth status: %@", self.diagnostics.authStatus))
                    Text(L10n.format(
                        "Plan type: %@",
                        self.diagnostics.planType?.uppercased() ?? L10n.text("unknown")
                    ))
                    Text(L10n.format(
                        "Current model: %@",
                        self.diagnostics.currentModel.isEmpty ? L10n.text("unknown") : self.diagnostics.currentModel
                    ))
                }

                Section(L10n.text("Health")) {
                    if let latency = self.diagnostics.lastPingLatencyMS {
                        Text(L10n.format(
                            "Ping latency: %@ ms",
                            latency.formatted(.number.precision(.fractionLength(0)))
                        ))
                    } else {
                        Text(L10n.text("Ping latency: unknown"))
                    }
                    Text(L10n.format("Reconnect attempts: %@", "\(self.diagnostics.reconnectAttemptCount)"))
                    if let lastPingAt = self.diagnostics.lastSuccessfulPingAt {
                        Text(L10n.format(
                            "Last successful ping: %@",
                            lastPingAt.formatted(date: .numeric, time: .standard)
                        ))
                    } else {
                        Text(L10n.text("Last successful ping: unknown"))
                    }
                    if let lastRPCErrorMessage = self.diagnostics.lastRPCErrorMessage {
                        let suffix = self.diagnostics.lastRPCErrorAt.map {
                            " (\($0.formatted(date: .omitted, time: .shortened)))"
                        } ?? ""
                        Text(L10n.format("Last RPC error: %@%@", lastRPCErrorMessage, suffix))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(L10n.text("Last RPC error: none"))
                    }
                }

                if !self.errorMessage.isEmpty {
                    Section {
                        Text(self.errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(L10n.text("Diagnostics"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        self.dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(L10n.text("Close"))
                    .codexActionButtonStyle()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.text("Run")) {
                        self.runDiagnostics()
                    }
                    .disabled(self.appState.appServerClient.state != .connected)
                    .codexActionButtonStyle()
                }
            }
        }
    }

    private func runDiagnostics() {
        self.errorMessage = ""
        Task {
            do {
                _ = try await self.appState.appServerClient.runDiagnostics()
            } catch {
                self.errorMessage = self.appState.appServerClient.userFacingMessage(for: error)
            }
        }
    }
}
