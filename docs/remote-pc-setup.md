# Codex Mobile Remote PC Setup (Tailscale)

この手順は iOS アプリからリモートPC上の Codex app-server を操作するための最小構成です。

## 1. リモートPCで Codex CLI を準備

```bash
codex --version
```

- `0.101.0` 以上であることを確認します。
- 未ログインの場合はログインします。

```bash
codex login
```

## 2. Tailscale 閉域網を準備

```bash
tailscale status
tailscale ip -4
```

- `100.x.x.x` の tailnet IP を控えます。
- iPhone 側も同じ tailnet に参加させます。

## 3. app-server を起動

```bash
codex app-server --listen ws://0.0.0.0:8080
```

- セキュリティ前提は Tailscale 閉域です。公開ネットワークへは直接公開しません。
- iOS 側接続URLは `ws://<tailnet-ip>:8080` を使います。

## 4. Tailscale ACL（例）

- iPhone のユーザー/デバイスからリモートPCの `8080/tcp` を許可します。
- それ以外からは遮断します。

## 5. iOS アプリで接続設定

- `Connections` タブで以下を登録
  - `Host`: リモートPCの tailnet IP
  - `App Server URL`: `ws://<tailnet-ip>:8080`
  - `Transport`: `App Server (WebSocket)`
- `Projects` タブで `remotePath` を追加
- `Threads` タブで `Connect` → `Refresh` を実行

## 6. 障害時フォールバック

- `Threads` 画面の `Open Fallback Terminal` から SSH ターミナルへ移動できます。
- app-server 停止時でも最低限の操作を継続できます。
