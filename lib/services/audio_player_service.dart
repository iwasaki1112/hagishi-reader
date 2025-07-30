import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../utils/time_formatter.dart';

class AudioPlayerService extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();
  
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  String? _currentFilePath;
  
  bool get isPlaying => _isPlaying;
  Duration get duration => _duration;
  Duration get position => _position;
  String? get currentFilePath => _currentFilePath;
  
  AudioPlayerService() {
    // プレイヤーの状態を監視
    _player.onPlayerStateChanged.listen((state) {
      _isPlaying = state == PlayerState.playing;
      notifyListeners();
    });
    
    _player.onDurationChanged.listen((duration) {
      _duration = duration;
      notifyListeners();
    });
    
    _player.onPositionChanged.listen((position) {
      _position = position;
      notifyListeners();
    });
    
    _player.onPlayerComplete.listen((_) {
      _isPlaying = false;
      _position = Duration.zero;
      _currentFilePath = null;
      notifyListeners();
    });
  }
  
  Future<bool> play(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        print('音声ファイルが見つかりません: $filePath');
        return false;
      }
      
      // 別のファイルが再生中の場合は停止
      if (_isPlaying && _currentFilePath != filePath) {
        await stop();
      }
      
      _currentFilePath = filePath;
      await _player.play(DeviceFileSource(filePath));
      print('再生開始: $filePath');
      return true;
    } catch (e) {
      print('再生エラー: $e');
      return false;
    }
  }
  
  Future<void> pause() async {
    try {
      await _player.pause();
      print('再生一時停止');
    } catch (e) {
      print('一時停止エラー: $e');
    }
  }
  
  Future<void> resume() async {
    try {
      await _player.resume();
      print('再生再開');
    } catch (e) {
      print('再開エラー: $e');
    }
  }
  
  Future<void> stop() async {
    try {
      await _player.stop();
      _position = Duration.zero;
      _currentFilePath = null;
      print('再生停止');
    } catch (e) {
      print('停止エラー: $e');
    }
  }
  
  Future<void> seek(Duration position) async {
    try {
      await _player.seek(position);
    } catch (e) {
      print('シークエラー: $e');
    }
  }
  
  Future<void> setVolume(double volume) async {
    try {
      await _player.setVolume((volume * 100).clamp(0, 100));
    } catch (e) {
      print('音量設定エラー: $e');
    }
  }
  
  String get formattedPosition => TimeFormatter.formatDuration(_position);
  
  String get formattedDuration => TimeFormatter.formatDuration(_duration);
  
  double get progress {
    if (_duration.inMilliseconds == 0) return 0.0;
    return _position.inMilliseconds / _duration.inMilliseconds;
  }
  
  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}