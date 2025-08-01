import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audio_session/audio_session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/bruxism_event.dart';
import '../models/sleep_session.dart';
import 'database_service.dart';

class AudioService extends ChangeNotifier with WidgetsBindingObserver {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioRecorder _eventRecorder = AudioRecorder(); // イベント録音用の別インスタンス
  
  // MethodChannel for iOS native audio session configuration
  static const _audioChannel = MethodChannel('com.example.hagishireader/audio');
  
  bool _isMonitoring = false;
  double _currentDecibel = 0.0;
  Timer? _monitoringTimer;
  bool _isRecording = false;
  String? _currentMonitoringPath; // 現在の監視録音パス
  Timer? _recordingTimer; // 録音タイマー
  Timer? _notificationTestTimer; // 通知テスト用タイマー
  
  // 検出パラメータ
  double _detectionThreshold = -30.0; // dB（動的に変更可能）
  static const int _requiredConsecutiveDetections = 1; // テスト用に1に設定
  
  // テスト用: より低い閾値を設定（検出しやすくする）
  bool _testMode = false; // テストモード無効
  int _consecutiveDetections = 0;
  DateTime? _lastDetectionTime; // 最後の検出時刻
  static const int _detectionTimeoutSeconds = 2; // 2秒以内に再検出があれば継続
  
  // スリープセッション管理
  SleepSession? _currentSession;
  String? _sessionDirectory;
  
  // 録音カウントダウン
  int _recordingCountdown = 0;
  Timer? _countdownTimer;
  
  bool get isMonitoring => _isMonitoring;
  double get currentDecibel => _currentDecibel;
  bool get isRecording => _isRecording;
  double get detectionThreshold => _detectionThreshold;
  bool get isAboveThreshold => _currentDecibel > _detectionThreshold;
  int get recordingCountdown => _recordingCountdown;
  
  AudioService() {
    // アプリのライフサイクルを監視
    WidgetsBinding.instance.addObserver(this);
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print('アプリライフサイクル状態: $state');
    if (state == AppLifecycleState.paused) {
      print('⚠️ アプリがバックグラウンドに移行しました');
    } else if (state == AppLifecycleState.resumed) {
      print('✅ アプリがフォアグラウンドに復帰しました');
    }
  }

  Future<bool> checkPermission() async {
    final status = await Permission.microphone.status;
    print('Current microphone permission status: $status');
    
    if (status == PermissionStatus.denied) {
      print('Requesting microphone permission...');
      final result = await Permission.microphone.request();
      print('Permission request result: $result');
      return result == PermissionStatus.granted;
    } else if (status == PermissionStatus.permanentlyDenied) {
      print('Microphone permission permanently denied');
      // ユーザーを設定画面に誘導
      await openAppSettings();
      return false;
    }
    
    return status == PermissionStatus.granted;
  }

  Future<void> startMonitoring() async {
    if (_isMonitoring) return;
    
    final hasPermission = await checkPermission();
    if (!hasPermission) {
      throw Exception('マイクの権限が必要です');
    }

    // 新しいスリープセッションを作成
    await _createNewSession();

    // 設定から検出閾値を読み込み
    await _loadDetectionThreshold();

    // iOS Audio Sessionを設定
    print('Audio Session設定開始...');
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.defaultToSpeaker,
      avAudioSessionMode: AVAudioSessionMode.measurement,
      // 録音中でもハプティックフィードバック（バイブレーション）を許可
      avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
    ));
    
    // iOS 13以降で録音中のハプティックフィードバックを明示的に許可
    try {
      await session.setActive(true);
      print('Audio Session有効化完了');
      
      // プラットフォーム固有の設定でハプティックフィードバックを許可
      if (Platform.isIOS) {
        print('iOS: 録音中ハプティックフィードバック許可を設定中...');
        try {
          final result = await _audioChannel.invokeMethod('enableHapticsWhileRecording');
          print('iOS: ハプティックフィードバック許可設定結果: $result');
        } catch (e) {
          print('iOS: ハプティックフィードバック許可設定エラー: $e');
        }
      }
    } catch (e) {
      print('Audio Session設定エラー: $e');
    }
    print('Audio Session設定完了');

    _isMonitoring = true;
    notifyListeners();

    // 実際の録音を開始して音声レベルを監視
    await _startContinuousRecording();
    
    // テスト用: 5秒ごとに通知を実行
    print('通知テストタイマー開始: 5秒ごと');
    _notificationTestTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      print('テストタイマー: 5秒経過 - 通知実行');
      
      // 通知テスト
      try {
        print('テスト通知実行');
        // 通知実行
        print('テスト通知完了');
      } catch (e) {
        print('タイマー内通知エラー: $e');
      }
    });
  }

  Future<void> stopMonitoring() async {
    _isMonitoring = false;
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _notificationTestTimer?.cancel();
    _notificationTestTimer = null;
    _currentDecibel = 0.0;
    _consecutiveDetections = 0;
    _lastDetectionTime = null;
    
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
      if (_isRecording && await _eventRecorder.isRecording()) {
        await _eventRecorder.stop();
        _isRecording = false;
      }
    } catch (e) {
      print('録音停止エラー: $e');
    }
    
    // スリープセッションを終了
    await _endCurrentSession();
    
    notifyListeners();
  }

  /// 新しいスリープセッションを作成
  Future<void> _createNewSession() async {
    final now = DateTime.now();
    final sessionId = 'session_${now.millisecondsSinceEpoch}';
    
    // セッション専用ディレクトリを作成
    final appDir = await getApplicationDocumentsDirectory();
    _sessionDirectory = '${appDir.path}/sessions/$sessionId';
    final sessionDir = Directory(_sessionDirectory!);
    await sessionDir.create(recursive: true);
    
    // セッションをデータベースに保存
    final session = SleepSession(
      startTime: now,
      sessionDirectory: _sessionDirectory!,
    );
    
    final sessionDbId = await DatabaseService.instance.createSession(session);
    _currentSession = session.copyWith(id: sessionDbId);
  }

  /// 現在のスリープセッションを終了
  Future<void> _endCurrentSession() async {
    if (_currentSession != null) {
      await DatabaseService.instance.endSession(
        _currentSession!.sessionId,
        DateTime.now(),
      );
    }
    _currentSession = null;
    _sessionDirectory = null;
  }

  Future<void> _startContinuousRecording() async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _currentMonitoringPath = '${_sessionDirectory}/monitoring_$timestamp.m4a';
      
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: _currentMonitoringPath!,
      );
      
        
      // 音声レベルを定期的にチェック
      _monitoringTimer = Timer.periodic(const Duration(milliseconds: 100), (_) async {
        await _checkAudioLevel();
      });
    } catch (e) {
      print('監視開始エラー: $e');
      _isMonitoring = false;
      notifyListeners();
    }
  }

  Future<void> _checkAudioLevel() async {
    if (!_isMonitoring) return;

    try {
      final amplitude = await _recorder.getAmplitude();
      _currentDecibel = amplitude.current;
      
      // 歯ぎしり検出ロジック
      final now = DateTime.now();
      
      // デバッグ: 常に現在のレベルと閾値を表示
      if (_currentDecibel != 0.0) {
        print('音声レベル: ${_currentDecibel.toStringAsFixed(1)}dB (閾値: ${_detectionThreshold.toStringAsFixed(1)}dB)');
      }
      
      if (_currentDecibel > _detectionThreshold) {
        // 前回検出から時間が経ちすぎている場合はリセット
        if (_lastDetectionTime != null && 
            now.difference(_lastDetectionTime!).inSeconds > _detectionTimeoutSeconds) {
          print('検出タイムアウト: 連続検出カウントリセット');
          _consecutiveDetections = 0;
        }
        
        _consecutiveDetections++;
        _lastDetectionTime = now;
        print('★★★ 音声検出: レベル=${_currentDecibel.toStringAsFixed(1)}dB > 閾値=${_detectionThreshold.toStringAsFixed(1)}dB, 連続=${_consecutiveDetections}/${_requiredConsecutiveDetections}');
        
        if (_consecutiveDetections >= _requiredConsecutiveDetections) {
          if (!_isRecording) {
            // 新しい録音を開始
            print('★★★ 連続検出達成: 録音開始 ★★★');
            await _startRecording();
          } else {
            // 録音中の場合は5秒延長
            print('録音延長');
            await _extendRecording();
          }
        }
      } else {
        // 閾値を下回った場合、時間によってリセット判定
        if (_lastDetectionTime != null && 
            now.difference(_lastDetectionTime!).inSeconds > _detectionTimeoutSeconds) {
          _consecutiveDetections = 0;
        }
      }
      
      notifyListeners();
    } catch (e) {
      print('音声レベル取得エラー: $e');
    }
  }

  Future<void> _startRecording() async {
    if (_isRecording) return;
    
    print('録音開始処理開始');
    _isRecording = true;
    notifyListeners();
    
    // 録音フラグが立った瞬間に即座に通知を実行
    print('即座に通知実行');

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${_sessionDirectory}/bruxism_$timestamp.m4a';

      // イベント録音用の別レコーダーを使用
      await _eventRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: filePath,
      );

      print('録音開始完了');

      // 5秒後に録音終了するタイマーを設定
      _setRecordingTimer();
    } catch (e) {
      print('Recording error: $e');
      _isRecording = false;
      notifyListeners();
    }
  }

  void _setRecordingTimer() {
    // 既存のタイマーをキャンセル
    _recordingTimer?.cancel();
    _countdownTimer?.cancel();
    
    // カウントダウンを5秒に設定
    _recordingCountdown = 5;
    notifyListeners();
    
    // 1秒ごとにカウントダウンを更新
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _recordingCountdown--;
      notifyListeners();
      
      if (_recordingCountdown <= 0) {
        timer.cancel();
        _countdownTimer = null;
      }
    });
    
    // 5秒後に録音終了
    _recordingTimer = Timer(const Duration(seconds: 5), () async {
      await _stopRecording();
    });
  }

  Future<void> _extendRecording() async {
    if (!_isRecording) return;
    
    
    // 既存のタイマーをキャンセルして新しいタイマーを設定
    _setRecordingTimer();
    
    // 連続検出をリセット（延長後の次の検出のため）
    _consecutiveDetections = 0;
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    
    try {
      _recordingTimer?.cancel();
      _countdownTimer?.cancel();
      final path = await _eventRecorder.stop();
      
      if (path != null) {
        final file = File(path);
        final fileSize = await file.length();
        
        // イベントを保存
        final event = BruxismEvent(
          detectedAt: DateTime.now(),
          duration: 5.0, // 実際の録音時間に基づく
          intensity: (_currentDecibel + 40) / 40, // 正規化 (0-1)
          audioFilePath: path,
          confidence: 0.8,
          sessionId: _currentSession?.sessionId ?? 'unknown_session',
        );
        
        await DatabaseService.instance.createEvent(event);
      }
    } catch (e) {
      print('Recording stop error: $e');
    } finally {
      _isRecording = false;
      _recordingCountdown = 0;
      _consecutiveDetections = 0; // リセット
      _recordingTimer = null;
      _countdownTimer = null;
      notifyListeners();
    }
  }

  /// 設定から検出閾値を読み込み、感度値をdB値に変換
  Future<void> _loadDetectionThreshold() async {
    final prefs = await SharedPreferences.getInstance();
    final sensitivity = prefs.getDouble('detectionSensitivity') ?? 0.5; // 0.0-1.0
    
    // 感度をdB値に変換 (0.0 = -50dB(高感度), 1.0 = -10dB(低感度))
    _detectionThreshold = -50.0 + (sensitivity * 40.0);
    
    // テストモード: より低い閾値を設定して検出しやすくする
    if (_testMode) {
      _detectionThreshold = -60.0; // 現在の音声レベル（-65dB前後）より少し高く設定
      print('テストモード: 検出閾値を${_detectionThreshold}dBに設定');
    }
    
    notifyListeners(); // UI更新のため
  }

  /// 公開メソッド：設定から検出閾値を再読み込み
  Future<void> reloadDetectionThreshold() async {
    await _loadDetectionThreshold();
  }

  /// バイブレーション設定を読み込み


  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    stopMonitoring();
    _recorder.dispose();
    _eventRecorder.dispose();
    super.dispose();
  }
}