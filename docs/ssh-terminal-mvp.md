# SSH Terminal MVP ノウハウ（CodexAppMobile）

最終更新: 2026-02-18

## 目的
- iOS Simulator 上で動く最小の SSH ターミナルアプリを構築する。
- 接続情報の一覧・追加・編集・削除（CRUD）を提供する。
- `make run-ios` / `make test-ios` で継続的に検証できる状態を保つ。

## 技術選定（2026-02-18 時点）
- `swift-nio-ssh` `0.12.0`（2025-11-06 公開）
  - SSH クライアント実装を Swift ネイティブで構築できる。
  - 参照: <https://api.github.com/repos/apple/swift-nio-ssh/releases/latest>
- `swift-nio-transport-services` `1.26.0`（2025-11-24 公開）
  - Apple プラットフォーム向けの Network.framework ベース transport。
  - 参照: <https://api.github.com/repos/apple/swift-nio-transport-services/releases/latest>
- `swift-nio` `2.94.1`（2026-02-11 公開）
  - NIO 系の最新基盤。
  - 参照: <https://api.github.com/repos/apple/swift-nio/releases/latest>

補足:
- 端末エミュレーション強化には `SwiftTerm`（`v1.10.1`）が候補だが、MVP は依存最小化のため未採用。
- 参照: <https://api.github.com/repos/migueldeicaza/SwiftTerm/releases/latest>

## 実装構成
対象ファイル:
- `CodexAppMobile/ContentView.swift`
- `CodexAppMobile/CodexAppMobileApp.swift`
- `CodexAppMobile.xcodeproj/project.pbxproj`
- `CodexAppMobile.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
- `CodexAppMobileTests/CodexAppMobileTests.swift`

主要コンポーネント:
- `ConnectionStore`
  - 接続先プロファイル配列を `UserDefaults` に保存。
  - パスワードは `Keychain`（`PasswordVault`）で管理。
- `ContentView` / `ConnectionEditorView`
  - 接続先の一覧・追加・編集・削除 UI。
- `TerminalSessionView` / `TerminalSessionViewModel`
  - 接続・切断、コマンド送信、出力表示を担当。
- `SSHClientEngine`
  - `NIOTSConnectionBootstrap` + `NIOSSHHandler` で SSH セッションを開始。
  - session channel 作成後に PTY 要求 + shell 要求を送信。

## MVP で割り切った点（既知）
- ホスト鍵検証は `AcceptAllHostKeysDelegate` で無条件許可（開発優先）。
- 認証はパスワードのみ（公開鍵認証は未実装）。
- 端末表示はプレーンテキスト表示（ANSI 完全対応のエミュレーターではない）。

## 実行・検証コマンド
作業ディレクトリ: `/Users/shuto/src/private/codex-app-mobile`

```bash
make run-ios
xcrun simctl list devices | rg "\(Booted\)"
xcrun simctl list devices | rg "CodexAppMobile iPhone 17"
make test-ios
```

## 次に強化する場合
1. ホスト鍵ピンニング（known_hosts 相当）を追加する。
2. 公開鍵認証（ED25519 等）と鍵管理 UI を追加する。
3. 端末エミュレーション（ANSI, cursor, resize）を改善する。
