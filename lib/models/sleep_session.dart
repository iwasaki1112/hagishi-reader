class SleepSession {
  final int? id;
  final DateTime startTime;
  final DateTime? endTime;
  final String sessionDirectory; // セッション専用ディレクトリパス
  final int eventCount; // このセッション内の録音イベント数
  
  SleepSession({
    this.id,
    required this.startTime,
    this.endTime,
    required this.sessionDirectory,
    this.eventCount = 0,
  });

  /// セッションの継続時間
  Duration get duration {
    final end = endTime ?? DateTime.now();
    return end.difference(startTime);
  }

  /// セッションが進行中かどうか
  bool get isActive => endTime == null;

  /// セッションIDを生成（日時ベース）
  String get sessionId {
    return 'session_${startTime.millisecondsSinceEpoch}';
  }

  /// フォーマットされた継続時間
  String get formattedDuration {
    final d = duration;
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    return '${hours}時間${minutes}分';
  }

  /// データベース用のMap変換
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'startTime': startTime.millisecondsSinceEpoch,
      'endTime': endTime?.millisecondsSinceEpoch,
      'sessionDirectory': sessionDirectory,
      'eventCount': eventCount,
    };
  }

  /// Mapからのインスタンス生成
  factory SleepSession.fromMap(Map<String, dynamic> map) {
    return SleepSession(
      id: map['id'],
      startTime: DateTime.fromMillisecondsSinceEpoch(map['startTime']),
      endTime: map['endTime'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(map['endTime'])
          : null,
      sessionDirectory: map['sessionDirectory'],
      eventCount: map['eventCount'] ?? 0,
    );
  }

  SleepSession copyWith({
    int? id,
    DateTime? startTime,
    DateTime? endTime,
    String? sessionDirectory,
    int? eventCount,
  }) {
    return SleepSession(
      id: id ?? this.id,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      sessionDirectory: sessionDirectory ?? this.sessionDirectory,
      eventCount: eventCount ?? this.eventCount,
    );
  }
}