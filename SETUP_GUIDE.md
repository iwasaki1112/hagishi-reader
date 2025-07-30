# HagishiReader セットアップガイド

## 📱 実機ビルド手順

### 1. Xcodeプロジェクトの作成

1. **Xcodeを開く**
   - Launchpadまたは`/Applications/Xcode.app`から起動

2. **新規プロジェクト作成**
   - "Create New Project" または メニューから File > New > Project を選択

3. **テンプレート選択**
   - iOS タブを選択
   - App を選択して Next

4. **プロジェクト設定**
   - **Product Name**: HagishiReader
   - **Team**: あなたのApple Developer Team（サインインが必要）
   - **Organization Identifier**: com.yourname（あなたの名前に変更）
   - **Bundle Identifier**: 自動生成される（例: com.yourname.HagishiReader）
   - **Interface**: SwiftUI
   - **Language**: Swift
   - **Use Core Data**: ✅ チェックを入れる
   - **Include Tests**: お好みで

5. **保存場所**
   - `/Users/iwasakishungo/Git/hagishireader` を選択
   - Create をクリック

### 2. 既存ファイルの追加

1. **ファイルを削除**
   - 自動生成された `ContentView.swift` を削除（Move to Trash）
   - 自動生成された `HagishiReaderApp.swift` を削除（Move to Trash）

2. **既存ファイルを追加**
   - プロジェクトナビゲータで HagishiReader フォルダを右クリック
   - "Add Files to HagishiReader..." を選択
   - 以下のフォルダを選択して追加:
     - `App/`
     - `Models/`
     - `Views/`
     - `Services/`
   - Options で "Create groups" を選択
   - Add をクリック

3. **Info.plistの更新**
   - プロジェクトナビゲータで Info.plist を選択
   - 既存の Info.plist の内容をコピーして置き換え

### 3. プロジェクト設定

1. **Signing & Capabilities**
   - プロジェクトナビゲータで HagishiReader プロジェクトを選択
   - TARGETS > HagishiReader を選択
   - Signing & Capabilities タブを開く
   - Team を選択（Apple IDでサインイン必要）
   - Bundle Identifier が一意であることを確認

2. **Deployment Info**
   - iOS 15.0 以上を選択
   - iPhone にチェック

3. **Background Modes**
   - "+ Capability" をクリック
   - "Background Modes" を追加
   - 以下にチェック:
     - ✅ Audio, AirPlay, and Picture in Picture
     - ✅ Background processing

### 4. 実機での実行

1. **デバイスを選択**
   - Xcode上部のデバイス選択メニューから "iPhone 12 mini" を選択

2. **ビルドと実行**
   - ⌘ + R でビルドと実行
   - または Product > Run メニューから実行

3. **初回実行時の設定**
   - iPhone側で通知が表示されたら:
     - 設定 > 一般 > デバイス管理
     - デベロッパAPPで開発者を信頼

### 5. トラブルシューティング

#### 証明書エラー
- Xcode > Preferences > Accounts でApple IDを追加
- Team でPersonal Teamを選択

#### Bundle IDエラー
- Bundle Identifierを一意のものに変更（例: com.yourname.hagishireader2024）

#### ビルドエラー
- Product > Clean Build Folder (⇧⌘K)
- DerivedDataを削除: `rm -rf ~/Library/Developer/Xcode/DerivedData`

#### デバイスが表示されない
1. iPhoneを再接続
2. iPhoneで「このコンピュータを信頼」を選択
3. Xcodeを再起動

## 🎯 実行確認

アプリが正常に起動したら、以下を確認：

1. **権限リクエスト**
   - マイクへのアクセス許可
   - 通知の許可

2. **基本機能**
   - ホーム画面の睡眠モード切り替え
   - 各タブの表示確認

3. **音声モニタリング**
   - 睡眠モードをONにして音声レベルが表示されることを確認

これで基本的なセットアップは完了です！