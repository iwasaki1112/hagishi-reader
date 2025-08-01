# 歯ぎしリーダー - Flutter版

Flutter で開発した iOS/Android 対応の歯ぎしり検出・録音アプリケーション

## 🌟 主な機能

- 🌙 **自動歯ぎしり検出**: バックグラウンドで音声をモニタリング
- 🎙️ **自動録音**: 検出時に前後の音声を含めて自動録音  
- 🗂️ **セッション管理**: 睡眠セッションごとに録音を整理
- 🔒 **プライバシー保護**: すべてのデータはデバイス内に保存
- 📱 **Material Design 3**: ダークモード対応の現代的なUI

## 🛠️ 技術スタック

- **Framework**: Flutter 3.x
- **言語**: Dart 3.7+
- **データベース**: SQLite (sqflite)
- **音声処理**: record パッケージ
- **状態管理**: Provider

## 📁 プロジェクト構造

```
lib/
├── main.dart                  # アプリのエントリーポイント
├── models/
│   ├── bruxism_event.dart     # 歯ぎしりイベントのデータモデル
│   └── sleep_session.dart     # 睡眠セッションのデータモデル
├── services/
│   ├── audio_service.dart     # 音声処理・検出サービス
│   └── database_service.dart  # データベース操作
├── screens/
│   ├── home_screen.dart       # ホーム画面（モニタリング）
│   ├── recordings_screen.dart # 録音リスト・再生画面
│   └── settings_screen.dart   # 設定画面
└── utils/
    └── time_formatter.dart    # 時刻フォーマットユーティリティ
```

## 🚀 セットアップ

### 1. 必要な環境

- Flutter SDK 3.0以上
- Dart 3.0以上
- iOS: Xcode 14以上
- Android: Android Studio / VS Code

### 2. 依存関係のインストール

```bash
flutter pub get
```

### 3. iOS権限設定

`ios/Runner/Info.plist` に以下が設定済み：

```xml
<key>NSMicrophoneUsageDescription</key>
<string>HagishiReaderは睡眠中の歯ぎしりを検出するために、マイクへのアクセスが必要です。</string>
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
    <string>background-processing</string>
</array>
```

## 📱 実機ビルド・実行

### iOS

```bash
# デバイス確認
flutter devices

# iPhone での実行
flutter run -d [DEVICE_ID]

# リリースビルド
flutter build ios --release
```

### Android

```bash
# Android での実行
flutter run -d [DEVICE_ID]

# APK ビルド
flutter build apk --release
```

## 🎯 使用方法

1. **権限許可**: 初回起動時にマイクアクセスを許可
2. **スリープモード開始**: ホーム画面の円をタップ
3. **自動検出**: 歯ぎしりが検出されると自動録音
4. **データ確認**: 録音タブで録音ファイルを確認
5. **設定調整**: 設定タブで検出感度や通知方法をカスタマイズ

## 📦 主要パッケージ

- `provider ^6.1.5`: 状態管理
- `record ^6.0.0`: 音声録音
- `sqflite ^2.4.2`: ローカルデータベース  
- `audio_session ^0.1.21`: オーディオセッション管理
- `permission_handler ^12.0.1`: 権限管理
- `shared_preferences ^2.5.3`: 設定保存
- `path_provider ^2.1.5`: ファイルパス取得
- `wakelock_plus ^1.2.10`: 画面ロック防止
- `flutter_slidable ^4.0.0`: スワイプアクション
- `intl ^0.20.2`: 国際化・日時フォーマット

## 🔧 開発・デバッグ

```bash
# ホットリロード付きで実行
flutter run

# ログ確認
flutter logs

# テスト実行
flutter test

# 静的解析
flutter analyze
```

## 📄 ライセンス

このプロジェクトはプライベートプロジェクトです。

## 🙋‍♂️ Swift版との違い

- ✅ **コード管理**: すべてコードで管理可能
- ✅ **クロスプラットフォーム**: iOS・Android両対応
- ✅ **コマンドライン**: GUI不要でビルド・デプロイ
- ✅ **依存関係**: pubspec.yamlで管理