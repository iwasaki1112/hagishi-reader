import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audio_session/audio_session.dart';
import 'dart:io';
import 'dart:async';

class TestPermissionsApp extends StatelessWidget {
  const TestPermissionsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Permission Test',
      home: const PermissionTestScreen(),
    );
  }
}

class PermissionTestScreen extends StatefulWidget {
  const PermissionTestScreen({super.key});

  @override
  State<PermissionTestScreen> createState() => _PermissionTestScreenState();
}

class _PermissionTestScreenState extends State<PermissionTestScreen> {
  String _permissionStatus = '未確認';
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  String? _recordingPath;
  String _recordingStatus = '未録音';
  Timer? _amplitudeTimer;
  double _currentAmplitude = 0.0;
  int _sampleCount = 0;
  
  // マイクテスト用の変数
  bool _isMicActive = false;
  double _peakAmplitude = -160.0;
  double _averageAmplitude = -160.0;
  List<double> _amplitudeHistory = [];
  String _micTestResult = 'テスト待機中';
  Color _micStatusColor = Colors.grey;
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('権限テスト'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'マイク権限状態: $_permissionStatus',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 10),
            Text(
              '録音状態: $_recordingStatus',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 10),
            Text(
              '音声レベル: ${_currentAmplitude.toStringAsFixed(1)} dB',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: _currentAmplitude > -30 ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'サンプル数: $_sampleCount',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: _micStatusColor, width: 2),
                borderRadius: BorderRadius.circular(8),
                color: _micStatusColor.withOpacity(0.1),
              ),
              child: Column(
                children: [
                  Text(
                    'マイクテスト結果',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _micTestResult,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: _micStatusColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'ピーク: ${_peakAmplitude.toStringAsFixed(1)} dB',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    '平均: ${_averageAmplitude.toStringAsFixed(1)} dB',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    '履歴: ${_amplitudeHistory.length} サンプル',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _checkPermission,
              child: const Text('権限状態を確認'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _requestPermission,
              child: const Text('権限をリクエスト'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _openSettings,
              child: const Text('設定を開く'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isRecording ? _stopRecording : _startRecording,
              child: Text(_isRecording ? '録音停止' : '録音開始'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isRecording ? Colors.red : Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _resetMicTest,
              child: const Text('マイクテストリセット'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Future<void> _checkPermission() async {
    final status = await Permission.microphone.status;
    setState(() {
      _permissionStatus = status.toString();
    });
  }
  
  Future<void> _requestPermission() async {
    final status = await Permission.microphone.request();
    setState(() {
      _permissionStatus = status.toString();
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('リクエスト結果: $status')),
    );
  }
  
  Future<void> _openSettings() async {
    await openAppSettings();
  }
  
  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        // iOS Audio Sessionを適切に設定
        print('Audio Session設定開始...');
        final session = await AudioSession.instance;
        await session.configure(AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.defaultToSpeaker,
          avAudioSessionMode: AVAudioSessionMode.measurement,
        ));
        print('Audio Session設定完了');
        
        final directory = await getApplicationDocumentsDirectory();
        final filePath = '${directory.path}/test_recording_${DateTime.now().millisecondsSinceEpoch}.m4a';
        
        // 録音設定を明示的に指定
        const recordConfig = RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
          numChannels: 1,
        );
        
        await _audioRecorder.start(recordConfig, path: filePath);
        print('録音開始: $filePath');
        
        setState(() {
          _isRecording = true;
          _recordingPath = filePath;
          _recordingStatus = '録音中...';
          _sampleCount = 0;
        });
        
        // 音声レベルを定期的に取得とマイクテスト
        _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) async {
          try {
            final amplitude = await _audioRecorder.getAmplitude();
            setState(() {
              _currentAmplitude = amplitude.current;
              _sampleCount++;
            });
            
            // マイクテスト処理
            _processMicTest(amplitude.current, amplitude.max);
            
            print('音声レベル: ${amplitude.current.toStringAsFixed(1)} dB (Max: ${amplitude.max.toStringAsFixed(1)} dB)');
          } catch (e) {
            print('音声レベル取得エラー: $e');
          }
        });
        
      } else {
        setState(() {
          _recordingStatus = '権限がありません';
        });
      }
    } catch (e) {
      print('録音エラー: $e');
      setState(() {
        _recordingStatus = 'エラー: $e';
      });
    }
  }
  
  Future<void> _stopRecording() async {
    try {
      _amplitudeTimer?.cancel();
      _amplitudeTimer = null;
      
      final path = await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
        _currentAmplitude = 0.0;
        _recordingStatus = path != null ? '録音完了: ${path.split('/').last}' : '録音失敗';
      });
      
      if (path != null) {
        final file = File(path);
        final fileSize = await file.length();
        print('録音ファイル保存: $path (${fileSize} bytes)');
        
        setState(() {
          _recordingStatus = '録音完了: ${path.split('/').last} (${fileSize} bytes)';
        });
      }
    } catch (e) {
      print('録音停止エラー: $e');
      setState(() {
        _recordingStatus = '停止エラー: $e';
        _isRecording = false;
        _currentAmplitude = 0.0;
      });
    }
  }
  
  void _processMicTest(double current, double max) {
    // 履歴に追加（最大100サンプル保持）
    _amplitudeHistory.add(current);
    if (_amplitudeHistory.length > 100) {
      _amplitudeHistory.removeAt(0);
    }
    
    // ピーク値更新
    if (current > _peakAmplitude) {
      _peakAmplitude = current;
    }
    
    // 平均値計算
    if (_amplitudeHistory.isNotEmpty) {
      _averageAmplitude = _amplitudeHistory.reduce((a, b) => a + b) / _amplitudeHistory.length;
    }
    
    // マイクテスト結果判定
    setState(() {
      if (_amplitudeHistory.length < 10) {
        _micTestResult = 'データ収集中...';
        _micStatusColor = Colors.blue;
      } else if (_peakAmplitude <= -50.0) {
        _micTestResult = '❌ マイク反応なし\n音を立ててください';
        _micStatusColor = Colors.red;
        _isMicActive = false;
      } else if (_peakAmplitude <= -35.0) {
        _micTestResult = '⚠️ 微弱な反応\nもう少し大きな音で';
        _micStatusColor = Colors.orange;
        _isMicActive = false;
      } else if (_peakAmplitude <= -20.0) {
        _micTestResult = '✅ マイク正常動作\n音声認識中';
        _micStatusColor = Colors.green;
        _isMicActive = true;
      } else {
        _micTestResult = '✅ 強い音声入力\nマイク動作良好';
        _micStatusColor = Colors.green;
        _isMicActive = true;
      }
      
      // デバッグ情報追加
      if (current == -32.0 && _sampleCount > 20) {
        _micTestResult += '\n🔍 -32dB固定値検出';
        _micStatusColor = Colors.purple;
      }
    });
  }
  
  void _resetMicTest() {
    setState(() {
      _peakAmplitude = -160.0;
      _averageAmplitude = -160.0;
      _amplitudeHistory.clear();
      _micTestResult = 'テスト待機中';
      _micStatusColor = Colors.grey;
      _isMicActive = false;
    });
    print('マイクテストをリセットしました');
  }
  
  @override
  void dispose() {
    _amplitudeTimer?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }
}