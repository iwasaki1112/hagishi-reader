import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:toastification/toastification.dart';
import '../services/audio_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    // アプリ終了時に画面ロックを確実に解除
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final audioService = Provider.of<AudioService>(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('歯ぎしりリーダー'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Fixed space for indicators (always reserved)
            SizedBox(
              height: 320, // Fixed height to prevent layout shift
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeInOut,
                child: audioService.isMonitoring
                  ? _buildIndicators(audioService)
                  : const SizedBox(),
              ),
            ),
            
            // Sleep Mode Button - Centered
            Expanded(
              child: Center(
                child: GestureDetector(
                  onTap: () async {
                    if (audioService.isMonitoring) {
                      // スリープモード解除時：画面ロックを解除
                      await WakelockPlus.disable();
                      await audioService.stopMonitoring();
                      
                      if (mounted) {
                        toastification.show(
                          context: context,
                          type: ToastificationType.success,
                          style: ToastificationStyle.fillColored,
                          title: const Text('スリープモード終了'),
                          description: const Text('画面ロックが有効化されました'),
                          alignment: Alignment.topCenter,
                          autoCloseDuration: const Duration(seconds: 3),
                          primaryColor: Colors.green,
                          icon: const Icon(Icons.nightlight_outlined),
                        );
                      }
                    } else {
                      try {
                        // 権限確認を明示的に実行
                        final hasPermission = await audioService.checkPermission();
                        if (hasPermission) {
                          // スリープモード開始時：画面ロックを防ぐ
                          await WakelockPlus.enable();
                          await audioService.startMonitoring();
                          
                          if (mounted) {
                            toastification.show(
                              context: context,
                              type: ToastificationType.info,
                              style: ToastificationStyle.fillColored,
                              title: const Text('スリープモード開始'),
                              description: const Text('画面ロックが無効化されました'),
                              alignment: Alignment.topCenter,
                              autoCloseDuration: const Duration(seconds: 3),
                              primaryColor: Colors.blue,
                              icon: const Icon(Icons.nightlight_round),
                            );
                          }
                        } else {
                          if (mounted) {
                            toastification.show(
                              context: context,
                              type: ToastificationType.warning,
                              style: ToastificationStyle.fillColored,
                              title: const Text('権限が必要です'),
                              description: const Text('設定画面でマイク権限を許可してください'),
                              alignment: Alignment.topCenter,
                              autoCloseDuration: const Duration(seconds: 5),
                              primaryColor: Colors.orange,
                              icon: const Icon(Icons.mic_off),
                            );
                          }
                        }
                      } catch (e) {
                        if (mounted) {
                          toastification.show(
                            context: context,
                            type: ToastificationType.error,
                            style: ToastificationStyle.fillColored,
                            title: const Text('エラーが発生しました'),
                            description: Text(e.toString()),
                            alignment: Alignment.topCenter,
                            autoCloseDuration: const Duration(seconds: 4),
                            primaryColor: Colors.red,
                            icon: const Icon(Icons.error),
                          );
                        }
                      }
                    }
                  },
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: audioService.isMonitoring
                          ? Colors.blue
                          : Colors.grey.shade800,
                      boxShadow: audioService.isMonitoring
                          ? [
                              BoxShadow(
                                color: Colors.blue.withOpacity(0.5),
                                blurRadius: 20,
                                spreadRadius: 5,
                              ),
                            ]
                          : [],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          audioService.isMonitoring
                              ? Icons.nightlight_round
                              : Icons.nightlight_outlined,
                          size: 60,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          audioService.isMonitoring ? 'モニタリング中' : 'スリープモード',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// インジケーター要素を構築するメソッド
  Widget _buildIndicators(AudioService audioService) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 音声レベルと閾値表示
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.graphic_eq, size: 20),
              const SizedBox(width: 8),
              Text(
                '現在: ${audioService.currentDecibel.toStringAsFixed(1)} dB',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(width: 16),
              Text(
                '閾値: ${audioService.detectionThreshold.toStringAsFixed(1)} dB',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // 閾値インジケーター
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 300,
            height: 50,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: audioService.isRecording 
                  ? Colors.red.withOpacity( 0.1)
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(25),
              border: Border.all(
                color: audioService.isRecording
                    ? Colors.red
                    : (audioService.isAboveThreshold 
                        ? Colors.orange.withOpacity( 0.8)
                        : Theme.of(context).colorScheme.outline.withOpacity( 0.3)),
                width: audioService.isRecording ? 3 : 2,
              ),
              boxShadow: audioService.isRecording ? [
                BoxShadow(
                  color: Colors.red.withOpacity( 0.3),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ] : null,
            ),
            child: Stack(
              children: [
                // 背景バー
                Container(
                  height: 34,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(17),
                  ),
                ),
                // 閾値ライン
                Positioned(
                  left: ((audioService.detectionThreshold + 50) / 50) * 284,
                  child: Container(
                    width: 3,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.orange.withOpacity( 0.5),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
                // 現在の音声レベルバー
                AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  height: 34,
                  width: ((audioService.currentDecibel + 50) / 50).clamp(0.0, 1.0) * 284,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: audioService.isRecording 
                          ? [Colors.red.withOpacity( 0.9), Colors.red.withOpacity( 0.6)]
                          : (audioService.isAboveThreshold 
                              ? [Colors.orange.withOpacity( 0.8), Colors.orange.withOpacity( 0.5)]
                              : [Colors.green.withOpacity( 0.7), Colors.green.withOpacity( 0.4)]),
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(17),
                    boxShadow: audioService.isAboveThreshold ? [
                      BoxShadow(
                        color: (audioService.isRecording ? Colors.red : Colors.orange).withOpacity( 0.3),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ] : null,
                  ),
                ),
                // ラベル
                Positioned(
                  left: 12,
                  top: 2,
                  child: Text(
                    '-50dB',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Positioned(
                  right: 12,
                  top: 2,
                  child: Text(
                    '0dB',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 8),
          
          // 状態表示
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Container(
              key: ValueKey(audioService.isRecording ? 'recording' : (audioService.isAboveThreshold ? 'above' : 'below')),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: audioService.isRecording 
                    ? Colors.red.withOpacity( 0.1)
                    : (audioService.isAboveThreshold 
                        ? Colors.orange.withOpacity( 0.1)
                        : Colors.green.withOpacity( 0.1)),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: audioService.isRecording 
                      ? Colors.red
                      : (audioService.isAboveThreshold ? Colors.orange : Colors.green),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    audioService.isRecording 
                        ? Icons.fiber_manual_record 
                        : (audioService.isAboveThreshold ? Icons.warning : Icons.check_circle),
                    size: 18,
                    color: audioService.isRecording 
                        ? Colors.red
                        : (audioService.isAboveThreshold ? Colors.orange : Colors.green),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    audioService.isRecording 
                        ? '録音中'
                        : (audioService.isAboveThreshold ? '閾値超過　検出中' : '監視中'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: audioService.isRecording 
                          ? Colors.red
                          : (audioService.isAboveThreshold ? Colors.orange : Colors.green),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // リアルタイム波形表示
          Container(
            width: 280,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity( 0.8),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: audioService.isRecording 
                    ? Colors.red.withOpacity( 0.5)
                    : Colors.green.withOpacity( 0.3),
                width: 1,
              ),
            ),
            child: CustomPaint(
              painter: RealtimeWaveformPainter(
                amplitude: audioService.currentDecibel,
                threshold: audioService.detectionThreshold,
                isRecording: audioService.isRecording,
                isAboveThreshold: audioService.isAboveThreshold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// リアルタイム波形表示用のPainter
class RealtimeWaveformPainter extends CustomPainter {
  final double amplitude;
  final double threshold;
  final bool isRecording;
  final bool isAboveThreshold;
  
  RealtimeWaveformPainter({
    required this.amplitude,
    required this.threshold,
    required this.isRecording,
    required this.isAboveThreshold,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    
    final centerY = size.height / 2;
    final timePoints = 50;
    
    // 背景グリッド
    final gridPaint = Paint()
      ..color = Colors.green.withOpacity( 0.2)
      ..strokeWidth = 0.5;
    
    // 水平グリッド線
    for (int i = 1; i < 4; i++) {
      final y = (size.height / 4) * i;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    
    // 閾値ライン
    final thresholdY = centerY - ((threshold + 50) / 50) * (centerY - 10);
    final thresholdPaint = Paint()
      ..color = Colors.orange
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    
    canvas.drawLine(
      Offset(0, thresholdY),
      Offset(size.width, thresholdY),
      thresholdPaint,
    );
    
    // ラベル
    final textPainter = TextPainter(
      text: TextSpan(
        text: '${threshold.toStringAsFixed(0)}dB',
        style: const TextStyle(
          color: Colors.orange,
          fontSize: 10,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(size.width - 35, thresholdY - 15));
    
    // 波形描画
    final path = Path();
    final normalizedAmplitude = ((amplitude + 50) / 50).clamp(0.0, 1.0);
    final waveHeight = normalizedAmplitude * (centerY - 10);
    
    paint.color = isRecording 
        ? Colors.red
        : (isAboveThreshold ? Colors.orange : Colors.green);
    
    // 疑似波形パターンを描画
    for (int i = 0; i < timePoints; i++) {
      final x = (size.width / timePoints) * i;
      final baseY = centerY;
      
      // 簡単な波形パターン
      final waveOffset = waveHeight * 
          (0.5 + 0.3 * ((i % 7) / 7) + 0.2 * ((i % 3) / 3));
      final y = baseY - waveOffset;
      
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    
    canvas.drawPath(path, paint);
    
    // 現在のレベルインジケーター
    final levelY = centerY - waveHeight;
    final levelPaint = Paint()
      ..color = paint.color
      ..style = PaintingStyle.fill;
    
    canvas.drawCircle(Offset(size.width - 20, levelY), 3, levelPaint);
    
    // 現在のレベル表示
    final levelTextPainter = TextPainter(
      text: TextSpan(
        text: '${amplitude.toStringAsFixed(0)}dB',
        style: TextStyle(
          color: paint.color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    levelTextPainter.layout();
    levelTextPainter.paint(canvas, Offset(10, 5));
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true; // 常に再描画してリアルタイム更新
  }
}