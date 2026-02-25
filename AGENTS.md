# AGENTS.md

This file defines development guidance for this repository.  
The goal is to ship working software quickly while keeping AI-driven iterative development maintainable.

## 1. Assumptions

- App Store release is not the immediate goal; prioritize local development and execution checks.
- Prioritize working behavior first, then improve incrementally with small diffs.
- When unsure, choose the option that adds less complexity.

## 2. Technology Policy (Actively Maintained Stack)

- Base stack: `Swift` + `SwiftUI` + `xcodebuild/simctl`.
- Use a stable Xcode version that works locally.
- Do not add external dependencies unless necessary.
- If a dependency is required, it must satisfy all of the following:
  - It has well-maintained official documentation.
  - It is actively maintained (at least one release or meaningful update within the last 12 months).
  - Its value over the no-dependency alternative is explicit.
- Before adding dependencies, obtain approval with rationale, alternatives, and impact scope.

## 3. Simple Architecture for AI-First Development

- Keep files small with a one-screen/one-responsibility bias.
- Avoid premature abstraction; defer heavy architecture until it is actually needed.
- Avoid global state; keep state management minimal and local when possible.
- Use straightforward names that reveal role and intent.
- Add only minimal comments that explain why, not obvious what.

## 4. Command-First Workflow

- Use `make` as the unified entrypoint for everyday operations.
- Standard commands:
  - `make setup-ios-runtime`: install iOS Simulator runtime
  - `make run-ios`: build and launch on Simulator
  - `make test-ios`: run tests
  - `make clean`: remove `.build`
- `run-ios` must not auto-download runtime; if missing, fail fast and instruct `setup-ios-runtime`.
- Limit Xcode GUI usage to initial project setup or UI debugging; use command-line flow for regular development.

## 5. Implementation Decision Order

- First, do not break existing behavior: respect current design, naming, and dependencies.
- Second, keep it simple: solve with minimal diffs.
- Third, extend only when required by real complexity.

## 6. Definition of Done (Minimum)

- Changes can be explained clearly at file level.
- Verification commands and their results are shared.
- Any skipped verification is explicitly noted with reason.

## 7. iOS Design Guidelines (Primary Sources)

- Prioritize Apple first-party guidance (HIG): https://developer.apple.com/jp/design/human-interface-guidelines/
- Keep screens function-minimal; avoid unnecessary decoration, information density, and navigation complexity.
- Design with Safe Area as a baseline, separating background and content scopes: https://developer.apple.com/documentation/uikit/positioning-content-relative-to-the-safe-area
- Prefer standard navigation and toolbar components; keep custom behavior minimal: https://developer.apple.com/documentation/swiftui/navigationstack
- Prefer Liquid Glass on supported OS versions, with standard-style fallback on older versions: https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
- Assume standard iOS keyboard behavior; disable autocorrection/capitalization only when required: https://developer.apple.com/documentation/uikit/uitextinputtraits
- Ensure keyboard appearance does not block core actions (dismiss affordance and scroll-dismiss): https://developer.apple.com/documentation/swiftui/view/scrolldismisseskeyboard(_:)
- Assume Codex communication flows through app-server. See: https://developers.openai.com/codex/app-server.md

## 8. Directory Structure

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
      SessionWorkbenchExecutionActions.swift
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

### Responsibility Split

- `App/`: app lifecycle and root wiring.
- `Features/Orchestration/`: host/project/thread domain, app-server client (core/parsing/payload), session workbench (core/UI/menu+connection/actions), and approval/diagnostics UI.
- `Features/Terminal/`: SSH terminal UI, shared style, ANSI rendering, and SSH transport engine.
- `scripts/`: local run/test and app-server helper automation.
