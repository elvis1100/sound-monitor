import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/calibration_profile.dart';
import '../models/session_model.dart';

final databaseServiceProvider = Provider<DatabaseService>((ref) {
  final service = DatabaseService();
  ref.onDispose(() => unawaited(service.close()));
  return service;
});

class DatabaseService {
  final String? databasePathOverride;
  final String? recordingsDirectoryOverride;
  Future<Database>? _openFuture;

  DatabaseService({
    this.databasePathOverride,
    this.recordingsDirectoryOverride,
  });

  Future<Database> get database => _openFuture ??= _openDatabase();

  Future<Database> _openDatabase() async {
    try {
      final path =
          databasePathOverride ??
          p.join(await getDatabasesPath(), 'sound_monitor.db');
      return await openDatabase(
        path,
        version: 6,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE sessions(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              title TEXT NOT NULL,
              date TEXT NOT NULL,
              minDb REAL NOT NULL,
              avgDb REAL NOT NULL,
              maxDb REAL NOT NULL,
              audioFilePath TEXT,
              audioDurationMilliseconds INTEGER,
              audioSampleRate INTEGER,
              hasLevelSamples INTEGER NOT NULL DEFAULT 1,
              recordingTimeline TEXT NOT NULL DEFAULT '[]',
              durationSeconds INTEGER NOT NULL,
              statsDurationSeconds INTEGER NOT NULL,
              measurementType TEXT NOT NULL DEFAULT 'legacyEstimate',
              frequencyWeighting TEXT NOT NULL DEFAULT 'a',
              timeResponse TEXT NOT NULL DEFAULT 'fast'
            )
          ''');
          await _createCalibrationTable(db);
          await _createAudioCleanupTable(db);
        },
        onUpgrade: (db, oldVersion, _) async {
          if (oldVersion < 2) {
            await db.execute(
              "ALTER TABLE sessions ADD COLUMN measurementType TEXT NOT NULL DEFAULT 'legacyEstimate'",
            );
            await _createCalibrationTable(db);
          }
          if (oldVersion < 3) {
            await db.execute(
              "ALTER TABLE sessions ADD COLUMN frequencyWeighting TEXT NOT NULL DEFAULT 'a'",
            );
            await db.execute(
              "ALTER TABLE sessions ADD COLUMN timeResponse TEXT NOT NULL DEFAULT 'fast'",
            );
          }
          if (oldVersion < 4) {
            await db.execute(
              "ALTER TABLE sessions ADD COLUMN statsDurationSeconds INTEGER NOT NULL DEFAULT 0",
            );
            await db.execute(
              "UPDATE sessions SET statsDurationSeconds = durationSeconds",
            );
          }
          if (oldVersion < 6) {
            await db.execute(
              'ALTER TABLE sessions ADD COLUMN audioDurationMilliseconds INTEGER',
            );
            await db.execute(
              'ALTER TABLE sessions ADD COLUMN audioSampleRate INTEGER',
            );
            await db.execute(
              'ALTER TABLE sessions ADD COLUMN hasLevelSamples INTEGER NOT NULL DEFAULT 1',
            );
            await db.execute(
              "ALTER TABLE sessions ADD COLUMN recordingTimeline TEXT NOT NULL DEFAULT '[]'",
            );
            await _createAudioCleanupTable(db);
          }
          if (oldVersion >= 2 && oldVersion < 5) {
            await db.execute(
              "ALTER TABLE calibration_profiles ADD COLUMN source TEXT NOT NULL DEFAULT 'reference'",
            );
          }
        },
      );
    } catch (_) {
      _openFuture = null;
      rethrow;
    }
  }

  static Future<void> _createCalibrationTable(DatabaseExecutor db) =>
      db.execute('''
        CREATE TABLE calibration_profiles(
          inputKey TEXT PRIMARY KEY,
          offsetDb REAL NOT NULL,
          calibratedAt TEXT NOT NULL,
          source TEXT NOT NULL DEFAULT 'reference'
        )
      ''');

  Future<int> insertSession(SessionModel session) async {
    final db = await database;
    return db.insert(
      'sessions',
      session.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Returns one page, newest first. Storage errors propagate to the caller.
  Future<List<SessionModel>> getSessions({
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await database;
    await _drainAudioCleanup(db);
    // History pages contain summaries; load the potentially long timeline only
    // when opening a recording, so paging does not load hours of samples.
    final rows = await db.query(
      'sessions',
      columns: [
        'id',
        'title',
        'date',
        'minDb',
        'avgDb',
        'maxDb',
        'audioFilePath',
        'audioDurationMilliseconds',
        'audioSampleRate',
        'hasLevelSamples',
        'durationSeconds',
        'statsDurationSeconds',
        'measurementType',
        'frequencyWeighting',
        'timeResponse',
      ],
      orderBy: 'date DESC, id DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(SessionModel.fromMap).toList(growable: false);
  }

  Future<SessionModel?> getSession(int id) async {
    final db = await database;
    final rows = await db.query(
      'sessions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : SessionModel.fromMap(rows.single);
  }

  Future<bool> renameSession(int id, String title) async {
    final value = title.trim();
    if (value.isEmpty || value.length > 100) return false;
    final db = await database;
    return await db.update(
          'sessions',
          {'title': value},
          where: 'id = ?',
          whereArgs: [id],
        ) >
        0;
  }

  static Future<void> _createAudioCleanupTable(DatabaseExecutor db) =>
      db.execute('CREATE TABLE audio_cleanup(path TEXT PRIMARY KEY)');

  Future<bool> deleteSession(int id) async {
    final db = await database;
    final deleted = await db.transaction((txn) async {
      final rows = await txn.query(
        'sessions',
        columns: ['audioFilePath'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return false;
      final path = rows.single['audioFilePath'] as String?;
      if (path != null && path.isNotEmpty) {
        await txn.insert('audio_cleanup', {
          'path': path,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      return await txn.delete('sessions', where: 'id = ?', whereArgs: [id]) > 0;
    });
    await _drainAudioCleanup(db);
    return deleted;
  }

  Future<void> clearAllSessions() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.rawInsert(
        "INSERT OR IGNORE INTO audio_cleanup(path) SELECT audioFilePath FROM sessions WHERE audioFilePath IS NOT NULL AND audioFilePath != ''",
      );
      await txn.delete('sessions');
    });
    await _drainAudioCleanup(db);
  }

  Future<void> _drainAudioCleanup(Database db) async {
    // Metadata deletion and its cleanup queue commit together. Failed file
    // deletion is retried on the next History load, without losing saved rows
    // during a failed database operation or reporting a committed delete as failed.
    for (final row in await db.query('audio_cleanup')) {
      final path = row['path'] as String;
      try {
        await _deleteOwnedAudio(path);
        await db.delete('audio_cleanup', where: 'path = ?', whereArgs: [path]);
      } catch (_) {
        // Retain the queue entry for a later retry.
      }
    }
  }

  Future<void> _deleteOwnedAudio(String audioPath) async {
    final normalized = p.normalize(p.absolute(audioPath));
    final recordings =
        recordingsDirectoryOverride ??
        p.join((await getApplicationSupportDirectory()).path, 'recordings');
    final extension = p.extension(normalized).toLowerCase();
    final ownedWav = extension == '.wav' && p.isWithin(recordings, normalized);
    final ownedLegacy =
        extension == '.pcm' &&
        p.isWithin((await getApplicationDocumentsDirectory()).path, normalized);
    if (!ownedWav && !ownedLegacy) return;
    final file = File(normalized);
    if (!await file.exists()) return;
    // Resolve links as well as lexical paths before deleting an owned file.
    final resolved = await file.resolveSymbolicLinks();
    final root = ownedWav
        ? recordings
        : (await getApplicationDocumentsDirectory()).path;
    if (!p.isWithin(await Directory(root).resolveSymbolicLinks(), resolved)) {
      return;
    }
    await file.delete();
  }

  Future<CalibrationProfile?> getCalibration(String inputKey) async {
    final db = await database;
    final rows = await db.query(
      'calibration_profiles',
      where: 'inputKey = ?',
      whereArgs: [inputKey],
      limit: 1,
    );
    return rows.isEmpty ? null : CalibrationProfile.fromMap(rows.single);
  }

  Future<void> saveCalibration(CalibrationProfile profile) async {
    final db = await database;
    await db.insert(
      'calibration_profiles',
      profile.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> clearCalibration(String inputKey) async {
    final db = await database;
    await db.delete(
      'calibration_profiles',
      where: 'inputKey = ?',
      whereArgs: [inputKey],
    );
  }

  Future<void> close() async {
    final dbFuture = _openFuture;
    if (dbFuture == null) return;
    try {
      final db = await dbFuture;
      if (db.isOpen) await db.close();
    } catch (_) {
      // Failed opening leaves no database to close.
    }
    _openFuture = null;
  }
}
