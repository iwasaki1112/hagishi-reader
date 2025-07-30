import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audio_session/audio_session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';
import '../models/bruxism_event.dart';
import '../models/sleep_session.dart';
import 'database_service.dart';

class AudioService extends ChangeNotifier {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioRecorder _eventRecorder = AudioRecorder(); // イベント録音用の別インスタンス
  
  bool _isMonitoring = false;
  double _currentDecibel = 0.0;
  Timer? _monitoringTimer;
  bool _isRecording = false;
  String? _currentMonitoringPath; // 現在の監視録音パス
  Timer? _recordingTimer; // 録音タイマー
  
  // 検出パラメータ
  double _detectionThreshold = -30.0; // dB（動的に変更可能）
  static const int _requiredConsecutiveDetections = 3; // 5→3に短縮
  int _consecutiveDetections = 0;
  DateTime? _lastDetectionTime; // 最後の検出時刻
  static const int _detectionTimeoutSeconds = 2; // 2秒以内に再検出があれば継続
  
  // スリープセッション管理
  SleepSession? _currentSession;
  String? _sessionDirectory;
  
  // バイブレーション設定
  bool _vibrationEnabled = true;
  
  bool get isMonitoring => _isMonitoring;
  double get currentDecibel => _currentDecibel;
  bool get isRecording => _isRecording;
  double get detectionThreshold => _detectionThreshold;
  bool get isAboveThreshold => _currentDecibel > _detectionThreshold;
  bool get vibrationEnabled => _vibrationEnabled;

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

    // 設定から検出閾値とバイブレーション設定を読み込み
    await _loadDetectionThreshold();
    await _loadVibrationSetting();

    // iOS Audio Sessionを設定
    print('Audio Session設定開始...');
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.defaultToSpeaker,
      avAudioSessionMode: AVAudioSessionMode.measurement,
    ));
    print('Audio Session設定完了');

    _isMonitoring = true;
    notifyListeners();

    // 実際の録音を開始して音声レベルを監視
    await _startContinuousRecording();
  }

  Future<void> stopMonitoring() async {
    _isMonitoring = false;
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
    _recordingTimer?.cancel();
    _recordingTimer = null;
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
      
      if (_currentDecibel > _detectionThreshold) {
        // 前回検出から時間が経ちすぎている場合はリセット
        if (_lastDetectionTime != null && 
            now.difference(_lastDetectionTime!).inSeconds > _detectionTimeoutSeconds) {
          _consecutiveDetections = 0;
        }
        
        _consecutiveDetections++;
        _lastDetectionTime = now;
        
        if (_consecutiveDetections >= _requiredConsecutiveDetections) {
          if (!_isRecording) {
            // 新しい録音を開始
            await _startRecording();
          } else {
            // 録音中の場合は5秒延長
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
    
    _isRecording = true;
    notifyListeners();
    
    // バイブレーションで録音開始を通知
    await _triggerVibration();

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
      _consecutiveDetections = 0; // リセット
      _recordingTimer = null;
      notifyListeners();
    }
  }

  /// 設定から検出閾値を読み込み、感度値をdB値に変換
  Future<void> _loadDetectionThreshold() async {
    final prefs = await SharedPreferences.getInstance();
    final sensitivity = prefs.getDouble('detectionSensitivity') ?? 0.5; // 0.0-1.0
    
    // 感度をdB値に変換 (0.0 = -50dB(高感度), 1.0 = -10dB(低感度))
    _detectionThreshold = -50.0 + (sensitivity * 40.0);
    notifyListeners(); // UI更新のため
  }

  /// 公開メソッド：設定から検出閾値を再読み込み
  Future<void> reloadDetectionThreshold() async {
    await _loadDetectionThreshold();
  }

  /// バイブレーション設定を読み込み
  Future<void> _loadVibrationSetting() async {
    final prefs = await SharedPreferences.getInstance();
    _vibrationEnabled = prefs.getBool('vibrationEnabled') ?? true;
    notifyListeners();
  }

  /// バイブレーション設定を保存
  Future<void> setVibrationEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('vibrationEnabled', enabled);
    _vibrationEnabled = enabled;
    notifyListeners();
  }

  /// バイブレーションを実行
  Future<void> _triggerVibration() async {
    if (!_vibrationEnabled) return;
    
    try {
      // デバイスがバイブレーションをサポートしているかチェック
      bool? hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        // 短いバイブレーション（200ms）
        await Vibration.vibrate(duration: 200);
      }
    } catch (e) {
      print('バイブレーションエラー: $e');
    }
  }

  @override
  void dispose() {
    stopMonitoring();
    _recorder.dispose();
    _eventRecorder.dispose();
    super.dispose();
  }
}