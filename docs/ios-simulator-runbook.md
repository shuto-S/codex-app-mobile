# iOS Simulator 運用ノウハウ（HelloWorldApp）

最終更新: 2026-02-17

## 目的
- `make run-ios` で「常に 1 台のみ Booted」を維持する。
- `make test-ios` を安定して通す。
- `run-ios` で runtime を自動ダウンロードしない方針を守る。

## 前提
- 作業ディレクトリ: `/Users/shuto/src/private/codex-app-mobile`
- 主な入口コマンド:
  - `make setup-ios-runtime`
  - `make run-ios`
  - `make test-ios`
  - `make clean`

## 標準フロー
1. 現状確認

```bash
git status --short
nl -ba scripts/run_ios.sh
```

2. runtime 確認（なければ明示導入）

```bash
xcrun simctl list runtimes
make setup-ios-runtime
```

3. アプリ起動

```bash
make run-ios
```

4. 単一起動チェック

```bash
xcrun simctl list devices | rg "\(Booted\)"
xcrun simctl list devices | rg "HelloWorldApp iPhone 17"
xcrun simctl list devices | rg "\(Booted\)" | wc -l
xcrun simctl list devices | rg "HelloWorldApp iPhone 17" | wc -l
```

5. テスト実行

```bash
make test-ios
```

6. 後片付け

```bash
make clean
git status --short
```

## 単一起動を担保する実装ポイント
対象: `scripts/run_ios.sh`

- 管理対象デバイス名を `HelloWorldApp iPhone 17` で固定。
- ロックディレクトリ（`.build/locks/run-ios.lock`）で `run-ios/test-ios` の同時実行を防止。
- 同名デバイスが複数ある場合は先頭 1 台を残して削除。
- 起動前に全デバイスを `shutdown` し、対象 UDID を明示して起動。
- 起動後に「対象以外で Booted な UDID」を shutdown。
- 最後に Booted 台数をカウントし、`1` 以外なら明示エラーで失敗させる。
- アプリ起動は以下オプションを使用（ハング回避/再起動安定化）:

```bash
xcrun simctl launch --terminate-running-process --stdout=/dev/null --stderr=/dev/null <device_udid> com.example.HelloWorldApp
```

## よくある失敗と対処
1. `No available iOS runtime found.`
- `make setup-ios-runtime` を実行して runtime を導入する。

2. `make run-ios` が完了しない
- `simctl launch` で標準出力接続に引っ張られる場合があるため、`--stdout=/dev/null --stderr=/dev/null` を使う。
- 既存プロセス競合は `--terminate-running-process` で回避する。

3. `make test-ios` で `Unable to find module dependency: 'HelloWorldApp'`
- `HelloWorldApp` ターゲットの Debug に `ENABLE_TESTABILITY = YES;` を設定する。
- 対象ファイル: `HelloWorldApp.xcodeproj/project.pbxproj`

## 受け入れチェックリスト
- `make run-ios` が成功する。
- `xcrun simctl list devices | rg "\(Booted\)" | wc -l` が `1`。
- `xcrun simctl list devices | rg "HelloWorldApp iPhone 17" | wc -l` が `1`（管理対象重複なし）。
- `make test-ios` が成功する。
- `git status --short` がクリーン（不要生成物は `make clean` で除去）。
