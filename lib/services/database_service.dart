import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/bruxism_event.dart';
import '../models/sleep_session.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('hagishi_reader.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future _createDB(Database db, int version) async {
    // スリープセッションテーブル
    await db.execute('''
      CREATE TABLE sleep_sessions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        startTime INTEGER NOT NULL,
        endTime INTEGER,
        sessionDirectory TEXT NOT NULL,
        eventCount INTEGER DEFAULT 0
      )
    ''');

    // 歯ぎしりイベントテーブル（sessionId追加）
    await db.execute('''
      CREATE TABLE bruxism_events(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        detectedAt INTEGER NOT NULL,
        duration REAL NOT NULL,
        intensity REAL NOT NULL,
        audioFilePath TEXT,
        confidence REAL NOT NULL,
        sessionId TEXT NOT NULL
      )
    ''');
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // スリープセッションテーブルを追加
      await db.execute('''
        CREATE TABLE sleep_sessions(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          startTime INTEGER NOT NULL,
          endTime INTEGER,
          sessionDirectory TEXT NOT NULL,
          eventCount INTEGER DEFAULT 0
        )
      ''');

      // 既存のbruxism_eventsテーブルにsessionIdカラムを追加
      await db.execute('ALTER TABLE bruxism_events ADD COLUMN sessionId TEXT DEFAULT "legacy_session"');
    }
  }

  // === スリープセッション管理 ===
  
  Future<int> createSession(SleepSession session) async {
    final db = await database;
    return await db.insert('sleep_sessions', session.toMap());
  }

  Future<List<SleepSession>> getAllSessions() async {
    final db = await database;
    final result = await db.query(
      'sleep_sessions',
      orderBy: 'startTime DESC',
    );
    return result.map((map) => SleepSession.fromMap(map)).toList();
  }

  Future<SleepSession?> getActiveSession() async {
    final db = await database;
    final result = await db.query(
      'sleep_sessions',
      where: 'endTime IS NULL',
      limit: 1,
    );
    if (result.isEmpty) return null;
    return SleepSession.fromMap(result.first);
  }

  Future<int> endSession(String sessionId, DateTime endTime) async {
    final db = await database;
    return await db.update(
      'sleep_sessions',
      {'endTime': endTime.millisecondsSinceEpoch},
      where: 'sessionDirectory LIKE ?',
      whereArgs: ['%$sessionId%'],
    );
  }

  Future<int> updateSessionEventCount(String sessionId, int eventCount) async {
    final db = await database;
    return await db.update(
      'sleep_sessions',
      {'eventCount': eventCount},
      where: 'sessionDirectory LIKE ?',
      whereArgs: ['%$sessionId%'],
    );
  }

  Future<int> deleteSession(int sessionId) async {
    final db = await database;
    
    // まず、このセッションの全イベントを削除
    await db.delete(
      'bruxism_events',
      where: 'sessionId LIKE ?',
      whereArgs: ['%session_$sessionId%'],
    );
    
    // セッション自体を削除
    return await db.delete(
      'sleep_sessions',
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  // === 歯ぎしりイベント管理 ===

  Future<int> createEvent(BruxismEvent event) async {
    final db = await database;
    final eventId = await db.insert('bruxism_events', event.toMap());
    
    // セッションのイベント数を更新
    final sessionEvents = await getEventsBySession(event.sessionId);
    await updateSessionEventCount(event.sessionId, sessionEvents.length);
    
    return eventId;
  }

  Future<List<BruxismEvent>> getAllEvents() async {
    final db = await database;
    final result = await db.query(
      'bruxism_events',
      orderBy: 'detectedAt DESC',
    );
    return result.map((map) => BruxismEvent.fromMap(map)).toList();
  }

  Future<List<BruxismEvent>> getEventsBySession(String sessionId) async {
    final db = await database;
    final result = await db.query(
      'bruxism_events',
      where: 'sessionId = ?',
      whereArgs: [sessionId],
      orderBy: 'detectedAt DESC',
    );
    return result.map((map) => BruxismEvent.fromMap(map)).toList();
  }

  Future<List<BruxismEvent>> getEventsByDateRange(DateTime start, DateTime end) async {
    final db = await database;
    final result = await db.query(
      'bruxism_events',
      where: 'detectedAt >= ? AND detectedAt <= ?',
      whereArgs: [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
      orderBy: 'detectedAt DESC',
    );
    return result.map((map) => BruxismEvent.fromMap(map)).toList();
  }

  Future<int> deleteEvent(int id) async {
    final db = await database;
    return await db.delete(
      'bruxism_events',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<Map<String, dynamic>> getStatistics(DateTime start, DateTime end) async {
    final events = await getEventsByDateRange(start, end);
    
    if (events.isEmpty) {
      return {
        'totalCount': 0,
        'totalDuration': 0.0,
        'averageDuration': 0.0,
        'averageIntensity': 0.0,
      };
    }

    final totalDuration = events.fold<double>(
      0,
      (sum, event) => sum + event.duration,
    );
    
    final totalIntensity = events.fold<double>(
      0,
      (sum, event) => sum + event.intensity,
    );

    return {
      'totalCount': events.length,
      'totalDuration': totalDuration,
      'averageDuration': totalDuration / events.length,
      'averageIntensity': totalIntensity / events.length,
    };
  }
}