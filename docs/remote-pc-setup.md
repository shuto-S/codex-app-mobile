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

## 5. iOS アプリで接続設定（現行UI）

1. `Hosts` タブで Host を追加
   - `Host`: リモートPCの tailnet IP
   - `App Server URL`: `ws://<tailnet-ip>:8080`
   - `Transport`: `App Server (WebSocket)`
2. `Hosts` タブから対象Hostをタップして `Sessions` タブへ遷移
3. `SessionWorkbench` で Project を追加
   - `Add Project` から `remotePath` を設定（必要に応じて `Browse Remote Path`）
4. 同画面で `Connect` -> `Refresh` を実行し、Thread を選択/新規作成

## 6. 障害時フォールバック

- `SessionWorkbench` の `Open in Terminal` で SSH Terminal に移動できます。
- app-server 停止時でも最低限の操作を継続できます。
