import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'dart:math';
import 'package:audio_waveforms/audio_waveforms.dart';
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
      body: SafeArea(
        child: _isLoading
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
                            return Container(
                              height: 60,
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: List.generate(waveformData.length, (index) {
                                  final progress = audioPlayer.progress.clamp(0.0, 1.0);
                                  final isActive = (index / waveformData.length) <= progress;
                                  final height = (waveformData[index] * 50).clamp(2.0, 50.0);
                                  
                                  return AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    width: 2,
                                    height: height,
                                    decoration: BoxDecoration(
                                      color: isCurrentlyPlaying && isActive
                                          ? Theme.of(context).colorScheme.primary
                                          : _getIntensityColor(waveformData[index]).withOpacity(0.7),
                                      borderRadius: BorderRadius.circular(1),
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

  void _togglePlayback(BruxismEvent event, AudioPlayerService audioPlayer) async {
    if (event.audioFilePath == null) return;
    
    if (audioPlayer.isPlaying && audioPlayer.currentFilePath == event.audioFilePath) {
      await audioPlayer.pause();
    } else if (!audioPlayer.isPlaying && audioPlayer.currentFilePath == event.audioFilePath) {
      await audioPlayer.resume();
    } else {
      await audioPlayer.play(event.audioFilePath!);
    }
  }

  Color _getIntensityColor(double intensity) {
    if (intensity < 0.3) return Colors.green;
    if (intensity < 0.7) return Colors.orange;
    return Colors.red;
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
      // 削除する音声ファイルが再生中の場合は停止
      final audioPlayer = Provider.of<AudioPlayerService>(context, listen: false);
      if (audioPlayer.currentFilePath == event.audioFilePath) {
        await audioPlayer.stop();
      }
      
      await DatabaseService.instance.deleteEvent(event.id!);
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
      final events = _sessionEvents[session.sessionId] ?? [];

      // セッション内のファイルが再生中の場合は停止
      final audioPlayer = Provider.of<AudioPlayerService>(context, listen: false);
      final isPlayingSessionFile = events.any((event) => 
        audioPlayer.currentFilePath == event.audioFilePath);
      if (isPlayingSessionFile) {
        await audioPlayer.stop();
      }

      // セッションディレクトリとすべてのファイルを削除
      final sessionDir = Directory(session.sessionDirectory);
      if (await sessionDir.exists()) {
        await sessionDir.delete(recursive: true);
      }

      // データベースからセッションと関連イベントを削除
      await DatabaseService.instance.deleteSession(session.id!);

      // UI更新
      await _loadSessions();

      // 削除完了
      print('セッション削除完了: ${events.length}件の録音');
    } catch (e) {
      print('セッション削除エラー: $e');
    }
  }
}
