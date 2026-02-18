# Codex Mobile Orchestration MVP実装計画（iOS / Tailscale閉域 / App-Server中心）

最終更新: 2026-02-18

## サマリー
- 目標は「リモートPC上のCodexをiOSから安全に操作するGUI」。
- 制御経路は `codex app-server`（WebSocket JSON-RPC）を主経路、既存SSHターミナルをフォールバックとして維持。
- 現在のUI導線は `Hosts -> Sessions -> Terminal`。
- 既存資産（SSH接続/Keychain/Known Hosts）を残し、最小差分で導入済み。

## 実装ステータス（2026-02-18）
- 完了: Host中心UI（3タブ: `Hosts / Sessions / Terminal`）
- 完了: `connection` 主要命名を `host` へ移行（互換デコード除く）
- 完了: `HostSessionStore` による再開コンテキスト永続化
- 完了: `SessionWorkbench`（Project/Thread/Prompt/Transcript/Approval）
- 完了: `AppServerClient`（initialize, ping, reconnect, timeout, thread/turn API）
- 完了: 承認フロー（command/file change/request user input）
- 完了: `TerminalLaunchContext` 経由の Terminal 遷移（`codex` / `codex resume` 自動投入）
- 完了: SSH簡易パスブラウザ（Project追加時）
- 完了: migration とRPC基本テスト追加

## 現行実装マップ（ファイル単位）
- `/Users/shuto/src/private/codex-app-mobile/CodexAppMobile/CodexOrchestration.swift`
  - ドメイン型: `RemoteHost`, `ProjectWorkspace`, `CodexThreadSummary`, `CodexTurnItem`
  - ストア: `RemoteHostStore`, `ProjectStore`, `ThreadBookmarkStore`, `HostSessionStore`
  - App Server: `AppServerClient`, `AppServerMessageRouter`
  - UI: `ContentView`, `HostsTabView`, `SessionsTabView`, `SessionWorkbenchView`, `HostDiagnosticsView`, `PendingRequestSheet`
  - SSH簡易ブラウザ: `RemotePathBrowserService`, `RemotePathBrowserView`
- `/Users/shuto/src/private/codex-app-mobile/CodexAppMobile/ContentView.swift`
  - SSH Terminal 本体、Known Hosts、フォールバック導線
- `/Users/shuto/src/private/codex-app-mobile/CodexAppMobile/CodexAppMobileApp.swift`
  - `AppState` 注入
- `/Users/shuto/src/private/codex-app-mobile/CodexAppMobileTests/CodexAppMobileTests.swift`
  - migration/RPC/ストア永続化/エラーカテゴリの単体テスト

## 採用技術スタック（確定）
- iOS: Swift + SwiftUI + Observation/Combine（既存準拠）
- 通信: `URLSessionWebSocketTask` + JSON-RPC 2.0
- 永続化: `UserDefaults`（設定/メタ）、`Keychain`（秘密情報）
- 接続: Tailscale閉域網内 `codex app-server --listen ws://<tailnet-ip>:<port>`
- フォールバック: 既存 `swift-nio-ssh` ベース端末
- 依存方針: MVPで新規外部依存は追加しない

## フェーズ進捗
1. フェーズ1（データモデル/永続化）: 完了
2. フェーズ2（App-Server通信基盤）: 完了
3. フェーズ3（GUI）: 完了（Host中心UIへ更新済み）
4. フェーズ4（承認/ユーザー入力/SSHフォールバック）: 完了
5. フェーズ5（運用導線/安定化）: 進行中

## フェーズ5の残タスク（次実装）
- unknown notification/プロトコル差分に対する退行テストの拡充
- 再接続時状態復元のテスト拡充
- 実機ネットワーク条件（切断/復帰）での検証ケース追加
- セットアップ文書の定期同期（UI文言変更追従）

## 受け入れ基準（MVP）
- Host管理: 複数Hostの登録・編集・削除
- Project管理: Hostごとに複数remote path保持
- Thread管理: 一覧/再開/新規開始/アーカイブ
- 入出力: ストリーミング表示と履歴再表示
- 承認: command/file change/request_user_input 応答
- 障害時: app-server不可でもSSH Terminalで操作継続

## リスクと対策
- `app-server` は experimental
  - 対策: CLI最小バージョン `0.101.0` を接続時チェック
- プロトコル変化によるUI崩壊
  - 対策: schema fixtureテストを段階的に追加し、未知通知は無視+ログ化
- モバイル回線品質
  - 対策: 自動再接続、turn中断、手動リトライ、Terminalフォールバック導線

## 前提
- 接続方式は `閉域網/Tailscale`
- 制御経路は `App-Server中心 + SSHフォールバック`
- 認証責務は `リモートPC管理`（モバイルにOpenAI鍵を保持しない）
- 対象は iOS 先行（Android 対象外）

## 参照（一次情報）
- [Codex CLI Features](https://developers.openai.com/codex/cli/features)
- [Codex CLI Reference](https://developers.openai.com/codex/cli/reference/)
- [Codex CLI Slash Commands](https://developers.openai.com/codex/cli/slash-commands)
- [Codex CLI App Server](https://developers.openai.com/codex/cli/app-server)
- [Codex CLI Non-interactive](https://developers.openai.com/codex/cli/non-interactive)
- [Codex CLI Config Basics](https://developers.openai.com/codex/cli/config)
- [Codex CLI Config Reference](https://developers.openai.com/codex/cli/config-reference)
- [openai/codex](https://github.com/openai/codex)
