---
applyTo: "CodexAppMobile/Features/Orchestration/**/*.swift"
---

- Keep app-server JSON-RPC compatibility as top priority.
- Preserve fallback behavior from app-server path to SSH Terminal path.
- Avoid changing approval/security behavior unless explicitly requested.
- When touching request/response parsing, add or update focused tests in `CodexAppMobileTests`.
- Validate with `make test-ios` and report failures with concrete command output summary.
