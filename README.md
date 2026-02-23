# CodexAppMobile

iOS からリモート PC 上の Codex を操作するための SwiftUI アプリです。  
主経路は `codex app-server`（WebSocket）、フォールバックとして SSH Terminal を備えています。

## 前提

- macOS + Xcode（`xcodebuild` / `simctl` が使えること）
- `make`
- （app-server 利用時）`codex` CLI と `node`
- （推奨）iPhone 側と同一 tailnet の Tailscale 環境

## クイックスタート

作業ディレクトリ: `/Users/shuto/src/private/codex-app-mobile`

```bash
make setup-ios-runtime
make run-ios
make test-ios
```

主要ターゲット:

- `make setup-ios-runtime`: iOS Simulator runtime を導入
- `make run-ios`: Simulator でビルド・起動（単一 Booted 管理）
- `make test-ios`: テスト実行
- `make run-app-server`: app-server + WS プロキシ起動
- `make clean`: `.build` を削除

## app-server 連携（最小）

リモート PC で起動:

```bash
make run-app-server
```

起動後、iOS 側は以下で接続します。

- 推奨: `ws://<tailnet-ip>:18081`（プロキシ経由）
- 直接: `ws://<tailnet-ip>:8080`（必要時のみ）

補足:

- 既定では app-server は `127.0.0.1:8080` に bind し、iOS は `18081` のプロキシへ接続します。
- `Sec-WebSocket-Extensions` によるハンドシェイク不整合を回避するため、プロキシを標準利用します。

## アプリ内の基本導線

1. `Hosts` タブで Host を追加
2. Host を選択して `Sessions` タブへ移動
3. `SessionWorkbench` で Project / Thread を選んで操作
4. 障害時は `Terminal` タブで SSH 操作へフォールバック

## ドキュメント

- `AGENTS.md`: 開発方針
- `docs/ios-simulator-runbook.md`: Simulator 運用手順
- `docs/remote-pc-setup.md`: Tailscale を使った接続手順
- `docs/ssh-terminal-mvp.md`: SSH Terminal MVP の実装メモ
- `docs/codex-mobile-orchestration-mvp-plan.md`: 全体実装計画
