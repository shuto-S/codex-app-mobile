---
applyTo: "CodexAppMobile/**/*.swift"
---

- Keep SwiftUI implementations simple and incremental.
- Prefer existing state flow (`AppState`, existing stores) over new global state.
- For UI updates, preserve current UX direction and iOS standard components.
- Do not introduce new external dependencies unless user approval is explicit.
- Verify with `make test-ios` after meaningful code changes.
