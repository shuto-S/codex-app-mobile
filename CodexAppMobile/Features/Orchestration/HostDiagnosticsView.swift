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
                Section("Host") {
                    Text("State: \(self.appState.appServerClient.state.rawValue)")
                    if !self.appState.appServerClient.connectedEndpoint.isEmpty {
                        Text(self.appState.appServerClient.connectedEndpoint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                Section("Codex CLI") {
                    Text("CLI version: \(self.diagnostics.cliVersion.isEmpty ? "unknown" : self.diagnostics.cliVersion)")
                    Text("Required >= \(self.diagnostics.minimumRequiredVersion)")
                    Text("Auth status: \(self.diagnostics.authStatus)")
                    Text("Current model: \(self.diagnostics.currentModel.isEmpty ? "unknown" : self.diagnostics.currentModel)")
                }

                Section("Health") {
                    if let latency = self.diagnostics.lastPingLatencyMS {
                        Text("Ping latency: \(latency.formatted(.number.precision(.fractionLength(0)))) ms")
                    } else {
                        Text("Ping latency: unknown")
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
            .navigationTitle("Diagnostics")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        self.dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                    .codexActionButtonStyle()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Run") {
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
