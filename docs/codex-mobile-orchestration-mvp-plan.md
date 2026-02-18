# Codex Mobile Orchestration MVP実装計画（iOS / Tailscale閉域 / App-Server中心）

最終更新: 2026-02-18

## サマリー
- 目標は「リモートPC上のCodexをiOSから安全に操作するGUI」。
- 方式は `codex app-server`（WebSocket JSON-RPC）を主経路、既存SSHターミナルを障害時フォールバック。
- MVP範囲は「接続管理 + プロジェクト管理 + スレッド管理 + 入出力表示 + 承認フロー」。
- 既存資産（SSH接続/Keychain/Known Hosts）を残し、最小差分で段階導入する。

## 調査結果（2026-02-18）
- ローカルCLIは `codex-cli 0.101.0`。`app-server` / `exec --json` / `resume` / `mcp` を確認。
- `app-server` は `--listen stdio://`（既定）と `--listen ws://IP:PORT` を提供。
- `app-server` プロトコルは `thread/*` `turn/*` `item/*` をJSON-RPCで提供し、通知ストリーミング（`item/agentMessage/delta` 等）に対応。
- `item/commandExecution/requestApproval` `item/fileChange/requestApproval` `item/tool/requestUserInput` をサーバー要求として処理可能。
- 現行アプリは `/Users/shuto/src/private/codex-app-mobile/CodexAppMobile/ContentView.swift` 内でSSH接続管理と端末表示まで実装済み。`make test-ios` は成功。

## 採用技術スタック（決定）
- iOS: Swift + SwiftUI + Observation/Combine（既存準拠）、`URLSessionWebSocketTask` でWS接続。
- プロトコル: JSON-RPC 2.0（Codex app-server schema準拠）。
- 永続化: `UserDefaults`（接続/プロジェクト/スレッドメタ）、`Keychain`（秘密情報）。
- リモート接続: Tailscale閉域網内で `codex app-server --listen ws://<tailnet-ip>:<port>`。
- フォールバック: 既存 `swift-nio-ssh` ベース端末を維持。
- 依存追加方針: MVPでは新規外部依存を追加しない（標準API+既存依存で実装）。

## 公開インターフェース/型の追加・変更
- 追加型（新規）
- `/Users/shuto/src/private/codex-app-mobile/CodexAppMobile/Domain/RemoteConnection.swift`: `RemoteConnection`, `TransportKind(appServerWS, ssh)`, `ConnectionAuthMode`。
- `/Users/shuto/src/private/codex-app-mobile/CodexAppMobile/Domain/ProjectWorkspace.swift`: `ProjectWorkspace(connectionId, remotePath, defaults...)`。
- `/Users/shuto/src/private/codex-app-mobile/CodexAppMobile/Domain/CodexThreadSummary.swift`: `threadId`, `preview`, `updatedAt`, `archived`。
- `/Users/shuto/src/private/codex-app-mobile/CodexAppMobile/Domain/CodexTurnItem.swift`: `ThreadItem`をUI表示可能なenumへ正規化。
- 追加APIクライアント
- `/Users/shuto/src/private/codex-app-mobile/CodexAppMobile/Infra/AppServer/AppServerClient.swift`: `connect()`, `initialize()`, `threadList()`, `threadStart()`, `threadResume()`, `turnStart()`, `turnSteer()`, `turnInterrupt()`, `respondApproval()`, `respondUserInput()`。
- `/Users/shuto/src/private/codex-app-mobile/CodexAppMobile/Infra/AppServer/AppServerMessageRouter.swift`: request/response correlation、notification dispatch。
- 既存変更
- `/Users/shuto/src/private/codex-app-mobile/CodexAppMobile/ContentView.swift`: タブ構成へ変更し、既存SSH画面を「Fallback Terminal」に移設。
- `/Users/shuto/src/private/codex-app-mobile/CodexAppMobile/CodexAppMobileApp.swift`: `AppState` 注入。
- `/Users/shuto/src/private/codex-app-mobile/CodexAppMobileTests/`: RPC schema準拠のdecode/flow testを追加。

## 実装フェーズ（決定済み）
1. フェーズ1: データモデルと永続化層
- `ConnectionStore` を `RemoteConnectionStore` に拡張し、`appServerWS` 情報を保持。
- `ProjectStore` と `ThreadBookmarkStore` を追加。
- 既存SSHプロファイルは起動時マイグレーションで新型へ変換（破壊的変更なし）。
- 受け入れ条件: 既存接続データを失わずに読み込める。新接続にWS情報を保存可能。

2. フェーズ2: App-Server通信基盤
- WebSocket接続、`initialize` 実装、heartbeat/reconnect/backoff実装。
- JSON-RPC request id 管理、timeout、cancel、error mappingを実装。
- `thread/list`, `thread/read`, `thread/start`, `thread/resume`, `turn/start`, `turn/steer`, `turn/interrupt` を最小実装。
- 受け入れ条件: リモートでスレッド一覧取得と1ターン送信ができる。

3. フェーズ3: GUI（MVP本体）
- 画面を `Connections` / `Projects` / `Threads` の3タブに分割。
- `Projects` で `connection + remotePath` を管理。
- `Threads` で thread list/read/start/resume、メッセージ入力、ストリーミング表示を実装。
- 受け入れ条件: プロジェクトを選んで会話継続できる。

4. フェーズ4: 承認・ユーザー入力・SSHフォールバック
- `item/commandExecution/requestApproval`, `item/fileChange/requestApproval`, `item/tool/requestUserInput` に対応したモーダルUIを実装。
- `accept/acceptForSession/decline/cancel` を送信可能にする。
- app-server切断時に1タップで既存SSHターミナルへ遷移。
- 受け入れ条件: 承認が必要なターンを中断せず操作完了できる。

5. フェーズ5: 運用導線と安定化
- 接続診断画面（CLI version, auth status, ping, current model）追加。
- リモートPCセットアップ手順を文書化（`codex login` / `codex app-server --listen ws://...` / Tailscale ACL）。
- エラーメッセージを利用者向けに分類（認証/接続/権限/互換性）。
- 受け入れ条件: 初見ユーザーが手順通りに接続完了できる。

## テストケースと検証シナリオ
- 単体テスト
- JSON-RPC decode/encode: `thread/*`, `turn/*`, `item/*`, approval payload。
- Store migration: 既存SSH保存形式 -> 新形式。
- Router: request-response correlation、unknown notification耐性、再接続時の状態復元。
- 結合テスト（ローカル）
- `make test-ios` を常時グリーン維持。
- モックWSで `item/agentMessage/delta` 連続到着時の描画整合性。
- 実機/実運用テスト
- Tailscale接続成功、thread list取得、turn開始、approval応答、turn完了。
- app-server停止時にSSHフォールバック導線が機能。
- セキュリティ確認
- Keychain以外に秘密情報を保存しない。
- ログ/クラッシュレポートにプロンプト本文や鍵情報を出さない。

## 受け入れ基準（MVP）
- 接続管理: 複数リモートPCの登録・編集・削除ができる。
- プロジェクト管理: 接続ごとに複数remote pathを持てる。
- スレッド管理: 一覧/再開/新規開始/アーカイブができる。
- 入出力: ストリーミング表示と履歴再表示ができる。
- 承認: command/file change/request_user_input の応答ができる。
- 障害時: app-server不可でもSSHターミナルで最低限の操作継続ができる。

## リスクと対策
- `app-server` は experimental。
- 対策: CLI最小バージョン `0.101.0` を接続時チェックし、非対応は明示エラー。
- プロトコル変化でUI崩壊のリスク。
- 対策: schema fixtureテストを追加し、未知イベントは無視+警告ログ。
- モバイル回線品質。
- 対策: 自動再接続、turn中断ボタン、手動リトライ、フォールバック導線。

## 前提・デフォルト（確定）
- 接続方式は `閉域網/Tailscale`。
- 制御経路は `App-Server中心 + SSHフォールバック`。
- 認証責務は `リモートPC管理`（モバイルにOpenAI鍵を保持しない）。
- MVP範囲は `接続 + プロジェクト + スレッド + 送受信 + 承認`。
- 対象は iOSアプリ先行（Androidは対象外）。
- 新規外部依存はMVPで追加しない。

## 参照（一次情報）
- [Codex CLI Features](https://developers.openai.com/codex/cli/features)
- [Codex CLI Reference](https://developers.openai.com/codex/cli/reference/)
- [Codex CLI Slash Commands](https://developers.openai.com/codex/cli/slash-commands)
- [Codex CLI App Server](https://developers.openai.com/codex/cli/app-server)
- [Codex CLI Non-interactive](https://developers.openai.com/codex/cli/non-interactive)
- [Codex CLI Config Basics](https://developers.openai.com/codex/cli/config)
- [Codex CLI Config Reference](https://developers.openai.com/codex/cli/config-reference)
- [openai/codex](https://github.com/openai/codex)
