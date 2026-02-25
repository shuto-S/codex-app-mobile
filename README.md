# CodexAppMobile

`CodexAppMobile` is a SwiftUI iOS app for operating Codex on a remote machine.  
It primarily communicates through `codex app-server` over WebSocket, with an SSH Terminal fallback when needed.

## Features

- Manage remote hosts (SSH and app-server endpoints)
- Manage threads per project workspace
- Chat with Codex, including create/resume/fork/archive thread flows
- Choose model, reasoning level, and collaboration mode
- Insert Slash Commands, MCP servers, and Skills from the `/` palette
- Handle app-server approval requests and user-input prompts
- Use SSH terminal fallback (including Known Hosts management)
- Receive local notifications when turns finish in the background

## Requirements

- iOS 18.0+ (Deployment Target: `18.0`)
- macOS + Xcode (`xcodebuild` / `simctl` available)
- `make`
- For app-server usage:
  - `codex` CLI
  - `node`
- Recommended network:
  - iPhone and remote machine connected to the same Tailnet (Tailscale)

## Tech Stack

- App: `Swift`, `SwiftUI`, `Swift Concurrency`
- SSH: [`swift-nio-ssh`](https://github.com/apple/swift-nio-ssh) + [`swift-nio-transport-services`](https://github.com/apple/swift-nio-transport-services)
- Markdown rendering: [`Textual`](https://github.com/gonzalezreal/textual)
- Dev/run tooling: `make`, `xcodebuild`, `simctl`
- Dependency licenses: [THIRD_PARTY_LICENSES.md](./THIRD_PARTY_LICENSES.md) (`Apache-2.0` / `MIT`)
- Connectivity:
  - Primary: `codex app-server` (WebSocket)
  - Helper: `ws_strip_extensions_proxy.js` (to avoid `Sec-WebSocket-Extensions` handshake issues)
  - Fallback: SSH (password authentication)

## Quick Start (Local)

```bash
make setup-ios-runtime
make run-ios
make test-ios
```

## Usage

### 1. Start app-server on your remote machine

```bash
make run-app-server
```

Default setup:
- app-server: `ws://127.0.0.1:18081`
- proxy: `ws://0.0.0.0:8080` (the iOS app should connect to this port)
- logs: `.build/logs/app-server.log`, `.build/logs/ws-proxy.log`

In the iOS app, do not use `localhost`. Use a reachable address instead, for example:  
`ws://<tailnet-ip>:8080`

### 2. Launch the app and register a host

On the `Hosts` screen, tap `+` and configure:
- Display name
- Host / SSH port / username / password
- App Server host / port (usually same host, port `8080`)
- Preferred transport (usually `App Server (WebSocket)`)

### 3. Create a project workspace

Open the host and add a project workspace (remote working directory).  
Optionally set default model and approval policy.

### 4. Chat in a thread

- Send prompts from the composer
- Use `/` palette items (Command / MCP / Skill)
- Run code review shortcuts when needed
- Respond to approval requests and input prompts in the UI

### 5. Fallback to SSH Terminal when needed

Use the host row context menu and open `Terminal` to operate directly over SSH.

## Development Commands

| Command | Description |
| --- | --- |
| `make setup-ios-runtime` | Install iOS Simulator runtime |
| `make run-ios` | Build and launch on Simulator |
| `make test-ios` | Run iOS tests |
| `make run-app-server` | Start `codex app-server` + WS proxy |
| `make clean` | Remove `.build` |

## Environment Variables

### `make run-ios`

- `IOS_DEVICE_NAME` (default: `CodexAppMobile iPhone 17`)
- `IOS_DEVICE_TYPE_IDENTIFIER` (default: `com.apple.CoreSimulator.SimDeviceType.iPhone-17`)

### `make run-app-server`

- `APP_SERVER_LISTEN_HOST` (default: `127.0.0.1`)
- `APP_SERVER_PORT` (default: `18081`)
- `APP_SERVER_PROXY_LISTEN_HOST` (default: `0.0.0.0`)
- `APP_SERVER_PROXY_PORT` (default: `8080`)
- `APP_SERVER_PROXY_UPSTREAM_HOST` (default: `127.0.0.1`)
- `APP_SERVER_PROXY_UPSTREAM_PORT` (default: same as `APP_SERVER_PORT`)

## Data Storage and Security

- Host credentials (passwords) are stored in iOS Keychain
- Host/project/thread metadata is stored in `UserDefaults`
- SSH host keys are stored with TOFU (trust on first use) and can be removed from Known Hosts
- `NSAllowsArbitraryLoads=true` is currently enabled for development convenience; review this before production/public distribution

## Troubleshooting

- `No iOS Simulator runtime found`:
  - Run `make setup-ios-runtime`
- `port is already in use`:
  - Free the port, or change `APP_SERVER_PORT` / `APP_SERVER_PROXY_PORT`
- iOS app cannot connect to app-server:
  - Use a reachable IP/hostname instead of `ws://localhost:...`
- app-server disconnects right after startup:
  - Check `.build/logs/app-server.log` and `.build/logs/ws-proxy.log`

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) for development and pull request guidelines.

## Security

See [SECURITY.md](./SECURITY.md) for responsible vulnerability reporting.

## References

- Codex app-server docs: [https://developers.openai.com/codex/app-server.md](https://developers.openai.com/codex/app-server.md)
- Apple Human Interface Guidelines: [https://developer.apple.com/design/human-interface-guidelines/](https://developer.apple.com/design/human-interface-guidelines/)

## License

- Project license: [LICENSE](./LICENSE) (MIT)
- Third-party dependency licenses: [THIRD_PARTY_LICENSES.md](./THIRD_PARTY_LICENSES.md)
- For distribution, include dependency `LICENSE` / `NOTICE` attributions as required
