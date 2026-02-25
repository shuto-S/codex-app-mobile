# CodexAppMobile Repository Instructions

## Project Summary
- `CodexAppMobile` is an iOS app to operate remote Codex sessions.
- Primary control path is `codex app-server` over WebSocket.
- SSH terminal is a fallback path when app-server is unavailable.

## Build/Test Entry Points
- Always start from this repository root.
- Primary commands:
  - `make run-ios`
  - `make test-ios`
  - `make run-app-server`

## Architecture Pointers
- App entry: `CodexAppMobile/App/CodexAppMobileApp.swift`
- Terminal feature: `CodexAppMobile/Features/Terminal/ContentView.swift`
- Orchestration domain/client: `CodexAppMobile/Features/Orchestration/CodexOrchestration.swift`
- Orchestration UI: `CodexAppMobile/Features/Orchestration/CodexOrchestrationViews.swift`
- Unit tests: `CodexAppMobileTests/CodexAppMobileTests.swift`

## Change Rules
- Respect existing naming/dependencies; prefer minimal diffs.
- Do not add new dependencies without explicit user approval.
- Avoid high-risk infra/security changes unless explicitly requested.
- After changes, run available verification commands and report exact results.
