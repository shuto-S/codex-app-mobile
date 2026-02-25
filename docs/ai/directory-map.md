# AI Directory Map

## Current Layout

```text
CodexAppMobile/
  App/
    CodexAppMobileApp.swift
  Features/
    Orchestration/
      AppServerClient.swift
      AppServerDomain.swift
      CodexOrchestration.swift
      CodexOrchestrationViews.swift
      HostDiagnosticsView.swift
      OrchestrationStores.swift
      PendingRequestSheet.swift
      SessionWorkbenchSupport.swift
      SessionWorkbenchView.swift
    Terminal/
      ContentView.swift
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
- `Features/Orchestration/`: host/project/thread domain, app-server client, session workbench, and approval/diagnostics UI.
- `Features/Terminal/`: SSH terminal UI and SSH engine/fallback path.
- `scripts/`: local run/test and app-server helper automation.
