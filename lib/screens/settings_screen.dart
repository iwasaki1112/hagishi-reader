import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:toastification/toastification.dart';
import '../services/audio_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  double _detectionSensitivity = 0.5;
  int _recordingDuration = 5;
  int _autoDeleteDays = 30;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _detectionSensitivity = prefs.getDouble('detectionSensitivity') ?? 0.5;
      _recordingDuration = prefs.getInt('recordingDuration') ?? 5;
      _autoDeleteDays = prefs.getInt('autoDeleteDays') ?? 30;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('detectionSensitivity', _detectionSensitivity);
    await prefs.setInt('recordingDuration', _recordingDuration);
    await prefs.setInt('autoDeleteDays', _autoDeleteDays);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
      ),
      body: ListView(
        children: [
          // Detection Settings
          _SectionHeader(title: '検出設定'),
          ListTile(
            title: const Text('検出感度'),
            subtitle: Slider(
              value: _detectionSensitivity,
              min: 0.0,
              max: 1.0,
              divisions: 10,
              label: '${(_detectionSensitivity * 100).toInt()}%',
              onChanged: (value) {
                setState(() {
                  _detectionSensitivity = value;
                });
                _saveSettings();
                
                // AudioServiceの閾値を更新
                final audioService = Provider.of<AudioService>(context, listen: false);
                audioService.reloadDetectionThreshold();
              },
            ),
          ),
          ListTile(
            title: const Text('録音時間'),
            trailing: DropdownButton<int>(
              value: _recordingDuration,
              items: const [
                DropdownMenuItem(value: 5, child: Text('5秒')),
                DropdownMenuItem(value: 10, child: Text('10秒')),
                DropdownMenuItem(value: 15, child: Text('15秒')),
                DropdownMenuItem(value: 20, child: Text('20秒')),
                DropdownMenuItem(value: 30, child: Text('30秒')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _recordingDuration = value;
                  });
                  _saveSettings();
                }
              },
            ),
          ),

          const SizedBox(height: 16),

          // Data Management
          _SectionHeader(title: 'データ管理'),
          ListTile(
            title: const Text('自動削除'),
            trailing: DropdownButton<int>(
              value: _autoDeleteDays,
              items: const [
                DropdownMenuItem(value: 30, child: Text('30日後')),
                DropdownMenuItem(value: 90, child: Text('90日後')),
                DropdownMenuItem(value: 0, child: Text('削除しない')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _autoDeleteDays = value;
                  });
                  _saveSettings();
                }
              },
            ),
          ),

          const SizedBox(height: 16),

          // About
          _SectionHeader(title: 'その他'),
          ListTile(
            title: const Text('使い方'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () => _showHelpDialog(context),
          ),
          ListTile(
            title: const Text('プライバシーポリシー'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () => _showPrivacyDialog(context),
          ),
          ListTile(
            title: const Text('このアプリについて'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () => _showAboutDialog(context),
          ),
          ListTile(
            title: const Text('バージョン'),
            trailing: const Text('1.0.0'),
          ),
        ],
      ),
    );
  }


  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('使い方'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('1. 枕元にiPhoneを置いて充電ケーブルを接続'),
              SizedBox(height: 8),
              Text('2. ホーム画面のスリープモードボタンをタップ'),
              SizedBox(height: 8),
              Text('3. 歯ぎしりを検出すると自動で5秒間録音'),
              SizedBox(height: 8),
              Text('4. 朝起きたらスリープモードを解除'),
              SizedBox(height: 8),
              Text('5. 録音タブで夜間の歯ぎしりを確認・再生'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  void _showPrivacyDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('プライバシーポリシー'),
        content: const SingleChildScrollView(
          child: Text(
            '歯ぎしリーダーは、すべての録音データをお使いのデバイス内にのみ保存します。外部サーバーへの送信は一切行いません。\n\n'
            '録音データは暗号化されてデバイス内に保存され、ユーザーの明示的な操作なしに共有されることはありません。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('歯ぎしリーダー'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.nightlight_round, size: 64, color: Colors.blue),
            SizedBox(height: 16),
            Text('睡眠中の歯ぎしりを自動検出・録音'),
            SizedBox(height: 16),
            Text('バージョン: 1.0.0'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}