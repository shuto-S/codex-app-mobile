# Where To Change

## Typical Task Mapping

| Task | Primary File(s) |
| --- | --- |
| App launch / foreground-background handling | `CodexAppMobile/App/CodexAppMobileApp.swift` |
| Host/session/thread data model or store behavior | `CodexAppMobile/Features/Orchestration/CodexOrchestration.swift`, `CodexAppMobile/Features/Orchestration/OrchestrationStores.swift` |
| app-server request/response handling | `CodexAppMobile/Features/Orchestration/AppServerClient.swift`, `CodexAppMobile/Features/Orchestration/AppServerClientParsing.swift`, `CodexAppMobile/Features/Orchestration/AppServerPayloads.swift`, `CodexAppMobile/Features/Orchestration/AppServerDomain.swift` |
| Hosts/Sessions screen UI | `CodexAppMobile/Features/Orchestration/CodexOrchestrationViews.swift` |
| Chat/workbench UI behavior | `CodexAppMobile/Features/Orchestration/SessionWorkbenchView.swift`, `CodexAppMobile/Features/Orchestration/SessionWorkbenchChatUI.swift`, `CodexAppMobile/Features/Orchestration/SessionWorkbenchPanels.swift`, `CodexAppMobile/Features/Orchestration/SessionWorkbenchMenuAndActions.swift`, `CodexAppMobile/Features/Orchestration/SessionWorkbenchExecutionActions.swift` |
| SSH codex実行/チャット変換ロジック | `CodexAppMobile/Features/Orchestration/SessionWorkbenchSupport.swift` |
| app-server承認リクエストUI | `CodexAppMobile/Features/Orchestration/PendingRequestSheet.swift` |
| 接続診断UI | `CodexAppMobile/Features/Orchestration/HostDiagnosticsView.swift` |
| SSH terminal behavior or known hosts flow | `CodexAppMobile/Features/Terminal/ContentView.swift`, `CodexAppMobile/Features/Terminal/CodexUIStyle.swift`, `CodexAppMobile/Features/Terminal/ANSIRenderer.swift`, `CodexAppMobile/Features/Terminal/SSHTransport.swift` |
| Regression/unit tests | `CodexAppMobileTests/CodexAppMobileTests.swift` |

## Verification Baseline

```bash
cd "$(git rev-parse --show-toplevel)"
make test-ios
```

If Simulator runtime is missing:

```bash
make setup-ios-runtime
```
