# Contributing

Thanks for helping improve CodexAppMobile.

## Development Setup

Run commands from the repository root.

```bash
make setup-ios-runtime
make test-ios
```

## Pull Request Guidelines

1. Keep changes minimal and aligned with existing naming and architecture.
2. Do not add dependencies without prior discussion and approval.
3. Include verification results (at minimum `make test-ios`) in the PR description.
4. Update related docs when behavior or workflow changes.

## Commit Hygiene

1. Avoid unrelated refactors in the same PR.
2. Never include secrets, private keys, or personal tokens in code, logs, or screenshots.
3. If a secret is exposed, rotate it immediately and redact it in follow-up communication.
