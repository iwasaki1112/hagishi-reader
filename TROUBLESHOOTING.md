# HagishiReader トラブルシューティングガイド

## 🚨 アプリがタップしてもすぐに落ちる問題

### 原因
**デバッグモードの制限**: iOS 14以降では、デバッグモードでビルドしたFlutterアプリは、Flutter toolsやXcodeが起動していない状態では実行できません。

### 解決方法

#### ✅ 方法1: リリースモードでビルド（推奨）
```bash
# リリースモードでビルド
flutter build ios --release

# デバイスにインストール
flutter install -d [DEVICE_ID]
```

#### ✅ 方法2: Flutter Runで起動
```bash
# Flutter toolsを使って起動（デバッグモード）
flutter run -d [DEVICE_ID]
```

#### ✅ 方法3: Xcodeから起動
1. `ios/Runner.xcworkspace` をXcodeで開く
2. 実機を選択
3. Run ボタンで実行

## 📱 起動後の確認手順

### 1. 権限設定の確認
- マイクアクセス許可
- 通知許可

### 2. 開発者証明書の信頼
1. **設定** → **一般** → **VPNとデバイス管理**
2. **デベロッパApp** → **Apple Development**
3. **「信頼」**をタップ

### 3. 基本機能テスト
1. ホーム画面の円をタップ（スリープモード開始）
2. 各タブの動作確認
3. 設定画面での各種設定

## 🔧 よくある問題と解決策

### Q: 証明書エラーが表示される
**A**: Apple IDでXcodeにサインインし、開発チームを設定

### Q: Bundle ID重複エラー
**A**: `ios/Runner.xcodeproj`で一意のBundle IDに変更

### Q: ビルドが失敗する
**A**: 
```bash
flutter clean
flutter pub get
cd ios && pod install && cd ..
flutter build ios --release
```

### Q: アプリアイコンが表示されない
**A**: `ios/Runner/Assets.xcassets/AppIcon.appiconset/`にアイコンを追加

## 📊 ログの確認方法

### Flutter logs
```bash
flutter logs -d [DEVICE_ID]
```

### Xcode Console
1. Window → Devices and Simulators
2. デバイスを選択
3. 「View Device Logs」でクラッシュログを確認

## 🎯 パフォーマンス最適化

### リリースビルドの推奨理由
- ✅ ホーム画面からの直接起動が可能
- ✅ 最適化されたバイナリサイズ
- ✅ 高速な実行速度
- ✅ バッテリー消費の最適化

### プロファイルビルド（テスト用）
```bash
flutter build ios --profile
```

## 📞 サポート

問題が解決しない場合は、以下の情報と共にお知らせください：

1. **デバイス情報**: iPhone モデル、iOS バージョン
2. **エラーメッセージ**: スクリーンショットまたはテキスト
3. **ビルドログ**: `flutter build ios --verbose`の出力
4. **実行環境**: Flutter バージョン、Xcode バージョン