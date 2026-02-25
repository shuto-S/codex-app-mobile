# AI Directory Map

## Current Layout

```text
CodexAppMobile/
  App/
    CodexAppMobileApp.swift
  Features/
    Orchestration/
      AppServerClient.swift
      AppServerClientParsing.swift
      AppServerDomain.swift
      AppServerPayloads.swift
      CodexOrchestration.swift
      CodexOrchestrationViews.swift
      HostDiagnosticsView.swift
      OrchestrationStores.swift
      PendingRequestSheet.swift
      SessionWorkbenchChatUI.swift
      SessionWorkbenchMenuAndActions.swift
      SessionWorkbenchPanels.swift
      SessionWorkbenchSupport.swift
      SessionWorkbenchView.swift
    Terminal/
      ANSIRenderer.swift
      CodexUIStyle.swift
      ContentView.swift
      SSHTransport.swift
  Assets.xcassets/
  Info.plist

CodexAppMobileTests/
  CodexAppMobileTests.swift

scripts/
  ensure_ios_runtime.sh
  run_ios.sh
  run_app_server_stack.sh
  ws_strip_extensions_proxy.js
```

## Responsibility Split
- `App/`: app lifecycle and root wiring.
- `Features/Orchestration/`: host/project/thread domain, app-server client (core/parsing/payload), session workbench (core/UI/actions), and approval/diagnostics UI.
- `Features/Terminal/`: SSH terminal UI, shared style, ANSI renderer, and SSH transport engine.
- `scripts/`: local run/test and app-server helper automation.
