# AGENTS.md

このファイルは本リポジトリの開発方針です。
目的は「動くものを最短で作る」「AIで継続開発しやすい状態を保つ」ことです。

## 1. 前提

- 当面は App Store リリースを目標にしない（ローカル開発と実行確認を優先）。
- まず動作を優先し、最小差分で改善を積み重ねる。
- 迷った場合は「複雑さを増やさない選択」を優先する。

## 2. 採用技術方針（活発に開発されているもの）

- 標準技術を基本とする: `Swift` + `SwiftUI` + `xcodebuild/simctl`。
- Xcode は安定版を使う（ローカルで動く最新安定系を優先）。
- 外部依存は原則追加しない。必要時のみ、以下を満たすこと。
- 公式ドキュメントが整備されている。
- 現在もメンテされている（直近 12 か月以内にリリース/更新がある）。
- その依存がない場合の代替案と比較して導入メリットが明確。
- 依存追加時は、理由・代替案・影響範囲を提示して承認を得てから実施する。

## 3. AI 主体開発のシンプル設計方針

- 1画面/1責務を基本に、ファイルを小さく保つ。
- 早すぎる抽象化をしない（重いアーキテクチャ導入は後回し）。
- グローバル状態を避け、必要最小の状態管理で実装する。
- 命名は役割が即わかる単純な名前にする。
- コメントは「なぜ必要か」が伝わる最小限のみ書く。

## 4. コマンド駆動方針（起動しやすさ）

- 日常操作は `make` を入口に統一する。
- 標準コマンド:
- `make setup-ios-runtime` : iOS Simulator runtime を導入
- `make run-ios` : Simulator 上でビルド・起動
- `make test-ios` : テスト実行
- `make clean` : `.build` を削除
- `run-ios` は runtime を自動ダウンロードしない。未導入時はエラーで停止し、`setup-ios-runtime` を案内する。
- Xcode GUI 操作は「初期作成」または「UIデバッグ」に限定し、通常開発はコマンド中心で行う。

## 5. 実装時の判断順序

- まず壊さない: 既存設計・命名・依存を尊重する。
- 次に単純: 最小差分で目的を達成する。
- 最後に拡張: 将来の複雑化は必要になってから対応する。

## 6. 完了条件（最低ライン）

- 変更内容をファイル単位で説明できる。
- 実行した検証コマンドと結果を共有できる。
- 未実施の検証があれば、理由を明記する。

## 7. iOS デザイン方針（URL付き）

- デザイン判断は Apple の一次情報を優先する（HIG）: https://developer.apple.com/jp/design/human-interface-guidelines/
- 画面は「機能ミニマム」を基本とし、不要な装飾・情報・操作導線を増やさない。
- レイアウトは Safe Area を前提に設計し、背景とコンテンツの適用範囲を分離する: https://developer.apple.com/documentation/uikit/positioning-content-relative-to-the-safe-area
- ナビゲーションやツールバーは標準コンポーネントを優先し、独自挙動は必要最小限にする: https://developer.apple.com/documentation/swiftui/navigationstack
- Liquid Glass は利用可能OSで優先採用し、古いOSでは標準スタイルへフォールバックする: https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
- テキスト入力は iOS 標準キーボードを前提とし、必要な場合のみ自動補正・自動大文字化を無効化する: https://developer.apple.com/documentation/uikit/uitextinputtraits
- キーボード表示中でも主要操作を阻害しない（閉じる導線、スクロールでの dismiss 等）: https://developer.apple.com/documentation/swiftui/view/scrolldismisseskeyboard(_:)
- Codexとの通信はapp-serverを介して行いうことを前提とする。ドキュメントを参照: https://developers.openai.com/codex/app-server.md
