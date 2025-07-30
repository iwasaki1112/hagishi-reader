class BruxismEvent {
  final int? id;
  final DateTime detectedAt;
  final double duration;
  final double intensity;
  final String? audioFilePath;
  final double confidence;
  final String sessionId; // 所属するスリープセッションのID

  BruxismEvent({
    this.id,
    required this.detectedAt,
    required this.duration,
    required this.intensity,
    this.audioFilePath,
    required this.confidence,
    required this.sessionId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'detectedAt': detectedAt.millisecondsSinceEpoch,
      'duration': duration,
      'intensity': intensity,
      'audioFilePath': audioFilePath,
      'confidence': confidence,
      'sessionId': sessionId,
    };
  }

  factory BruxismEvent.fromMap(Map<String, dynamic> map) {
    return BruxismEvent(
      id: map['id'],
      detectedAt: DateTime.fromMillisecondsSinceEpoch(map['detectedAt']),
      duration: map['duration'],
      intensity: map['intensity'],
      audioFilePath: map['audioFilePath'],
      confidence: map['confidence'],
      sessionId: map['sessionId'] ?? 'unknown_session',
    );
  }

  String get formattedDuration {
    final dur = Duration(seconds: duration.toInt());
    final minutes = dur.inMinutes;
    final seconds = dur.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

}