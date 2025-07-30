import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'dart:math';
import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:toastification/toastification.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../models/bruxism_event.dart';
import '../models/sleep_session.dart';
import '../services/database_service.dart';
import '../services/audio_player_service.dart';

class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({super.key});

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> 
    with SingleTickerProviderStateMixin {
  List<SleepSession> _sessions = [];
  Map<String, List<BruxismEvent>> _sessionEvents = {}; // セッション別イベント
  bool _isLoading = true;
  late AnimationController _animationController;
  final Map<String, List<double>> _waveformCache = {}; // 波形データキャッシュ

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _animationController.repeat();
    _loadSessions();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadSessions() async {
    final sessions = await DatabaseService.instance.getAllSessions();
    final Map<String, List<BruxismEvent>> sessionEvents = {};
    
    // 各セッションのイベントを取得
    for (final session in sessions) {
      final events = await DatabaseService.instance.getEventsBySession(session.sessionId);
      sessionEvents[session.sessionId] = events;
    }
    
    setState(() {
      _sessions = sessions;
      _sessionEvents = sessionEvents;
      _isLoading = false;
    });
  }

  /// 音声ファイルから波形データを抽出
  Future<List<double>> _extractWaveformData(String filePath) async {
    // キャッシュから取得を試行
    if (_waveformCache.containsKey(filePath)) {
      return _waveformCache[filePath]!;
    }

    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return List.filled(50, 0.0);
      }

      // PlayerControllerを使用して波形データを抽出
      final controller = PlayerController();
      try {
        await controller.preparePlayer(
          path: filePath,
          shouldExtractWaveform: true,
          noOfSamples: 50,
        );

        // 波形データを取得（少し待機してから取得）
        await Future.delayed(const Duration(milliseconds: 100));
        final waveformData = controller.waveformData;

        if (waveformData != null && waveformData.isNotEmpty) {
          // データを正規化 (0.0-1.0の範囲に変換)
          final maxValue = waveformData.reduce((a, b) => a.abs() > b.abs() ? a : b).abs();
          final normalizedData = maxValue > 0 
              ? waveformData.map((value) => (value.abs() / maxValue)).toList()
              : List.filled(50, 0.0);
          
          // キャッシュに保存
          _waveformCache[filePath] = normalizedData;
          return normalizedData;
        }
      } finally {
        controller.dispose();
      }
    } catch (e) {
      print('波形抽出エラー: $e');
    }

    // エラーまたはデータなしの場合はデフォルト波形を返す
    final defaultWaveform = List.generate(50, (index) => 0.2);
    _waveformCache[filePath] = defaultWaveform;
    return defaultWaveform;
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('録音データ'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _sessions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.bedtime_off,
                        size: 80,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'スリープセッションがありません',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'スリープモードを使用すると、セッションが表示されます',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                      ),
                    ],
                  ),
                )
              : SlidableAutoCloseBehavior(
                  child: ListView.builder(
                    itemCount: _sessions.length,
                    padding: const EdgeInsets.all(8),
                    itemBuilder: (context, index) {
                      final session = _sessions[index];
                      final events = _sessionEvents[session.sessionId] ?? [];
                      
                      return _buildSessionCard(session, events);
                    },
                  ),
                ),
    );
  }

  Widget _buildSessionCard(SleepSession session, List<BruxismEvent> events) {
    final dateFormat = DateFormat('MM/dd HH:mm');
    
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Slidable(
        key: Key('session_${session.id}'),
        endActionPane: ActionPane(
          motion: const ScrollMotion(),
          extentRatio: 0.25, // スワイプエリアの幅を画面の25%に設定
          children: [
            SlidableAction(
              onPressed: (context) async {
                final shouldDelete = await _showDeleteModal(session);
                if (shouldDelete) {
                  await _deleteSession(session);
                }
              },
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              icon: Icons.delete_forever,
              label: '削除',
              borderRadius: BorderRadius.circular(12),
            ),
          ],
        ),
        child: ExpansionTile(
          leading: CircleAvatar(
            backgroundColor: session.isActive ? Colors.blue : Colors.green,
            child: Icon(
              session.isActive ? Icons.bedtime : Icons.check_circle,
              color: Colors.white,
            ),
          ),
          title: Text(
            '${dateFormat.format(session.startTime)} - ${session.endTime != null ? dateFormat.format(session.endTime!) : "進行中"}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            '${session.formattedDuration} • 録音: ${events.length}件',
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
          children: events.isEmpty
              ? [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'このセッションでは録音はありませんでした',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.outline,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ]
              : events.map((event) => _buildEventTile(event)).toList(),
        ),
      ),
    );
  }

  Widget _buildEventTile(BruxismEvent event) {
    final timeFormat = DateFormat('HH:mm:ss');
    
    return Consumer<AudioPlayerService>(
      builder: (context, audioPlayer, child) {
        final isCurrentFile = audioPlayer.currentFilePath == event.audioFilePath;
        final isCurrentlyPlaying = audioPlayer.isPlaying && isCurrentFile;
        
        return Column(
          children: [
            ListTile(
              leading: Icon(
                Icons.graphic_eq,
                color: _getIntensityColor(event.intensity),
              ),
              title: Text(timeFormat.format(event.detectedAt)),
              subtitle: Row(
                children: [
                  Icon(Icons.timer, size: 16, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(width: 4),
                  Text(event.formattedDuration),
                  const SizedBox(width: 12),
                  Icon(Icons.shield, size: 16, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(width: 4),
                  Text('${(event.confidence * 100).toInt()}%'),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      isCurrentlyPlaying 
                        ? Icons.pause_circle_outline 
                        : Icons.play_circle_outline,
                      color: isCurrentlyPlaying 
                        ? Theme.of(context).colorScheme.primary 
                        : null,
                    ),
                    onPressed: () => _togglePlayback(event, audioPlayer),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _confirmDelete(event),
                  ),
                ],
              ),
            ),
            // 再生中のプログレスバー表示
            if (isCurrentFile && audioPlayer.duration.inMilliseconds > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text(
                          audioPlayer.formattedPosition,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 3,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                              ),
                              child: Slider(
                                value: audioPlayer.progress.clamp(0.0, 1.0),
                                onChanged: (value) {
                                  final position = Duration(
                                    milliseconds: (audioPlayer.duration.inMilliseconds * value).round(),
                                  );
                                  audioPlayer.seek(position);
                                },
                                activeColor: Theme.of(context).colorScheme.primary,
                                inactiveColor: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                              ),
                            ),
                          ),
                        ),
                        Text(
                          audioPlayer.formattedDuration,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // 実際の音声データに基づく波形表示
                    FutureBuilder<List<double>>(
                      future: _extractWaveformData(event.audioFilePath ?? ''),
                      builder: (context, snapshot) {
                        final waveformData = snapshot.data ?? List.filled(50, 0.2);
                        
                        return AnimatedBuilder(
                          animation: _animationController,
                          builder: (context, child) {
                            return SizedBox(
                              height: 32,
                              child: Row(
                                children: List.generate(50, (index) {
                                  final progress = audioPlayer.progress;
                                  final isActive = (index / 50) <= progress;
                                  
                                  // 実際の波形データから高さを計算
                                  final baseHeight = (waveformData[index] * 24) + 4; // 4-28の範囲
                                  
                                  // 再生中のアニメーション効果
                                  final animationOffset = audioPlayer.isPlaying && isActive
                                    ? (sin((_animationController.value * pi * 2) + (index * 0.2)) * 2)
                                    : 0.0;
                                  
                                  final height = (baseHeight + animationOffset).clamp(2.0, 28.0);
                                  
                                  return Expanded(
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(horizontal: 0.5),
                                      height: height,
                                      decoration: BoxDecoration(
                                        color: isActive 
                                          ? (audioPlayer.isPlaying 
                                              ? Theme.of(context).colorScheme.primary.withOpacity(0.9)
                                              : Theme.of(context).colorScheme.primary.withOpacity(0.6))
                                          : Theme.of(context).colorScheme.outline.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(1.5),
                                        boxShadow: isActive && audioPlayer.isPlaying ? [
                                          BoxShadow(
                                            color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                                            blurRadius: 2,
                                            spreadRadius: 0.5,
                                          )
                                        ] : null,
                                      ),
                                    ),
                                  );
                                }),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Color _getIntensityColor(double intensity) {
    if (intensity < 0.3) return Colors.green;
    if (intensity < 0.7) return Colors.orange;
    return Colors.red;
  }

  Future<void> _togglePlayback(BruxismEvent event, AudioPlayerService audioPlayer) async {
    if (event.audioFilePath == null) {
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          style: ToastificationStyle.fillColored,
          title: const Text('ファイルエラー'),
          description: const Text('音声ファイルが見つかりません'),
          alignment: Alignment.topCenter,
          autoCloseDuration: const Duration(seconds: 3),
          primaryColor: Colors.red,
          icon: const Icon(Icons.error_outline),
        );
      }
      return;
    }
    
    // ファイルの存在確認
    final file = File(event.audioFilePath!);
    if (!await file.exists()) {
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.warning,
          style: ToastificationStyle.fillColored,
          title: const Text('ファイルが見つかりません'),
          description: const Text('音声ファイルが削除されています'),
          alignment: Alignment.topCenter,
          autoCloseDuration: const Duration(seconds: 3),
          primaryColor: Colors.orange,
          icon: const Icon(Icons.folder_off),
        );
      }
      return;
    }
    
    final isCurrentlyPlaying = audioPlayer.isPlaying && 
      audioPlayer.currentFilePath == event.audioFilePath;
    
    if (isCurrentlyPlaying) {
      await audioPlayer.pause();
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.info,
          style: ToastificationStyle.fillColored,
          title: const Text('一時停止'),
          description: const Text('再生を一時停止しました'),
          alignment: Alignment.topCenter,
          autoCloseDuration: const Duration(seconds: 2),
          primaryColor: Colors.blue,
          icon: const Icon(Icons.pause_circle),
        );
      }
    } else if (audioPlayer.currentFilePath == event.audioFilePath) {
      // 同じファイルの再開
      await audioPlayer.resume();
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.success,
          style: ToastificationStyle.fillColored,
          title: const Text('再生再開'),
          description: const Text('再生を再開しました'),
          alignment: Alignment.topCenter,
          autoCloseDuration: const Duration(seconds: 2),
          primaryColor: Colors.green,
          icon: const Icon(Icons.play_circle),
        );
      }
    } else {
      // 新しいファイルの再生
      final success = await audioPlayer.play(event.audioFilePath!);
      if (success && mounted) {
        final dateFormat = DateFormat('MM/dd HH:mm');
        toastification.show(
          context: context,
          type: ToastificationType.success,
          style: ToastificationStyle.fillColored,
          title: const Text('再生開始'),
          description: Text('${dateFormat.format(event.detectedAt)}の録音を再生中'),
          alignment: Alignment.topCenter,
          autoCloseDuration: const Duration(seconds: 4),
          primaryColor: Colors.green,
          icon: const Icon(Icons.play_circle_filled),
        );
      } else if (!success && mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          style: ToastificationStyle.fillColored,
          title: const Text('再生エラー'),
          description: const Text('再生に失敗しました'),
          alignment: Alignment.topCenter,
          autoCloseDuration: const Duration(seconds: 3),
          primaryColor: Colors.red,
          icon: const Icon(Icons.error),
        );
      }
    }
  }

  Future<void> _confirmDelete(BruxismEvent event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('削除確認'),
        content: const Text('この録音データを削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('削除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && event.id != null) {
      await DatabaseService.instance.deleteEvent(event.id!);
      
      // 削除したファイルが再生中の場合は停止
      final audioPlayer = context.read<AudioPlayerService>();
      if (audioPlayer.currentFilePath == event.audioFilePath) {
        await audioPlayer.stop();
      }
      
      await _loadSessions();
    }
  }

  Future<bool> _showDeleteModal(SleepSession session) async {
    final events = _sessionEvents[session.sessionId] ?? [];
    
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('セッションを削除'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('このスリープセッションを完全に削除しますか？'),
            const SizedBox(height: 8),
            Text(
              '• 録音データ: ${events.length}件',
              style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
                fontSize: 14,
              ),
            ),
            Text(
              '• セッションフォルダとすべてのファイルが削除されます',
              style: TextStyle(
                color: Colors.red,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'この操作は元に戻せません。',
              style: TextStyle(
                color: Colors.red,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('削除', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ) ?? false;
  }


  Future<void> _deleteSession(SleepSession session) async {
    try {
      // 再生中の音声があれば停止
      final audioPlayer = context.read<AudioPlayerService>();
      final events = _sessionEvents[session.sessionId] ?? [];
      
      for (final event in events) {
        if (audioPlayer.currentFilePath == event.audioFilePath) {
          await audioPlayer.stop();
          break;
        }
      }

      // セッションディレクトリとすべてのファイルを削除
      final sessionDir = Directory(session.sessionDirectory);
      if (await sessionDir.exists()) {
        await sessionDir.delete(recursive: true);
      }

      // データベースからセッションと関連イベントを削除
      await DatabaseService.instance.deleteSession(session.id!);

      // 波形キャッシュをクリア
      for (final event in events) {
        if (event.audioFilePath != null) {
          _waveformCache.remove(event.audioFilePath!);
        }
      }

      // UI更新
      await _loadSessions();

      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.success,
          style: ToastificationStyle.fillColored,
          title: const Text('削除完了'),
          description: Text('セッション (${events.length}件の録音) を削除しました'),
          alignment: Alignment.topCenter,
          autoCloseDuration: const Duration(seconds: 3),
          primaryColor: Colors.green,
          icon: const Icon(Icons.check_circle),
        );
      }
    } catch (e) {
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          style: ToastificationStyle.fillColored,
          title: const Text('削除エラー'),
          description: Text('セッションの削除に失敗しました: ${e.toString()}'),
          alignment: Alignment.topCenter,
          autoCloseDuration: const Duration(seconds: 4),
          primaryColor: Colors.red,
          icon: const Icon(Icons.error),
        );
      }
    }
  }
}
