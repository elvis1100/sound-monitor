import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sound_level_monitor/models/calibration_profile.dart';
import 'package:sound_level_monitor/models/measurement_settings.dart';
import 'package:sound_level_monitor/models/session_model.dart';
import 'package:sound_level_monitor/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'version 1 sessions migrate without losing data or claiming calibration',
    () async {
      final directory = await Directory.systemTemp.createTemp('sound-db-test-');
      final path = p.join(directory.path, 'sound_monitor.db');
      addTearDown(() => directory.delete(recursive: true));

      final oldDb = await openDatabase(
        path,
        version: 1,
        onCreate: (db, _) => db.execute('''
        CREATE TABLE sessions(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT,
          date TEXT,
          minDb REAL,
          avgDb REAL,
          maxDb REAL,
          audioFilePath TEXT,
          durationSeconds INTEGER
        )
      '''),
      );
      await oldDb.insert('sessions', {
        'title': 'Old session',
        'date': '2026-09-01T10:00:00.000',
        'minDb': 40,
        'avgDb': 50,
        'maxDb': 60,
        'audioFilePath': null,
        'durationSeconds': 30,
      });
      await oldDb.close();

      final service = DatabaseService(databasePathOverride: path);
      final oldSessions = await service.getSessions();
      expect(oldSessions, hasLength(1));
      expect(oldSessions.single.title, 'Old session');
      expect(oldSessions.single.statsDurationSeconds, 30);
      expect(
        oldSessions.single.measurementType,
        MeasurementType.legacyEstimate,
      );
      expect(await (await service.database).getVersion(), 6);

      final profile = CalibrationProfile.fromReference(
        inputKey: 'android_built_in_mic_v1_44100',
        referenceDb: 75,
        measuredDbFs: -24,
        calibratedAt: DateTime.utc(2026, 9, 30),
      );
      await service.saveCalibration(profile);
      await service.insertSession(
        SessionModel(
          id: 1001,
          title: 'New session',
          date: DateTime.utc(2026, 9, 30),
          minDb: 60,
          avgDb: 70,
          maxDb: 80,
          durationSeconds: 45,
          statsDurationSeconds: 15,
          measurementType: MeasurementType.referenceAdjustedDbC,
          frequencyWeighting: FrequencyWeighting.c,
          timeResponse: TimeResponse.impulse,
        ),
      );
      expect(await service.getSessions(limit: 1), hasLength(1));
      expect(
        (await service.getSessions(limit: 1, offset: 1)).single.measurementType,
        MeasurementType.legacyEstimate,
      );
      await service.close();

      final reopened = DatabaseService(databasePathOverride: path);
      final oldProfile = await reopened.getCalibration(profile.inputKey);
      expect(oldProfile?.offsetDb, 99);
      expect(oldProfile?.source, CalibrationSource.reference);
      expect(
        (await reopened.getSessions(limit: 1)).single.measurementType,
        MeasurementType.referenceAdjustedDbC,
      );
      expect(
        (await reopened.getSessions(limit: 1)).single.frequencyWeighting,
        FrequencyWeighting.c,
      );
      expect(
        (await reopened.getSessions(limit: 1)).single.timeResponse,
        TimeResponse.impulse,
      );
      expect(
        (await reopened.getSessions(limit: 1)).single.statsDurationSeconds,
        15,
      );
      await reopened.close();
    },
  );

  test(
    'version 2 sessions gain default weighting without losing calibration',
    () async {
      final directory = await Directory.systemTemp.createTemp('sound-db-v2-');
      final path = p.join(directory.path, 'sound_monitor.db');
      addTearDown(() => directory.delete(recursive: true));
      final db = await openDatabase(
        path,
        version: 2,
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
            durationSeconds INTEGER NOT NULL,
            measurementType TEXT NOT NULL DEFAULT 'legacyEstimate'
          )
        ''');
          await db.execute('''
          CREATE TABLE calibration_profiles(
            inputKey TEXT PRIMARY KEY,
            offsetDb REAL NOT NULL,
            calibratedAt TEXT NOT NULL
          )
        ''');
        },
      );
      await db.insert('sessions', {
        'title': 'Previous estimate',
        'date': '2026-09-30T10:00:00',
        'minDb': 50,
        'avgDb': 60,
        'maxDb': 70,
        'durationSeconds': 12,
        'measurementType': 'estimatedDbA',
      });
      await db.insert('calibration_profiles', {
        'inputKey': 'android_built_in_mic_v1_44100',
        'offsetDb': 92.0,
        'calibratedAt': '2026-09-30T10:00:00',
      });
      await db.close();

      final service = DatabaseService(databasePathOverride: path);
      final row = (await service.getSessions()).single;
      expect(row.measurementType, MeasurementType.estimatedDbA);
      expect(row.frequencyWeighting, FrequencyWeighting.a);
      expect(row.timeResponse, TimeResponse.fast);
      expect(row.statsDurationSeconds, 12);
      expect(
        (await service.getCalibration(
          'android_built_in_mic_v1_44100',
        ))?.offsetDb,
        92,
      );
      expect(
        (await service.getCalibration('android_built_in_mic_v1_44100'))?.source,
        CalibrationSource.reference,
      );
      await service.close();
    },
  );

  test('version 3 sessions gain a full statistics window on upgrade', () async {
    final directory = await Directory.systemTemp.createTemp('sound-db-v3-');
    final path = p.join(directory.path, 'sound_monitor.db');
    addTearDown(() => directory.delete(recursive: true));
    final db = await openDatabase(
      path,
      version: 3,
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
            durationSeconds INTEGER NOT NULL,
            measurementType TEXT NOT NULL DEFAULT 'legacyEstimate',
            frequencyWeighting TEXT NOT NULL DEFAULT 'a',
            timeResponse TEXT NOT NULL DEFAULT 'fast'
          )
        ''');
        await db.execute('''
          CREATE TABLE calibration_profiles(
            inputKey TEXT PRIMARY KEY,
            offsetDb REAL NOT NULL,
            calibratedAt TEXT NOT NULL
          )
        ''');
      },
    );
    await db.insert('sessions', {
      'title': 'Previous C session',
      'date': '2026-09-30T10:00:00',
      'minDb': 40,
      'avgDb': 60,
      'maxDb': 90,
      'durationSeconds': 90,
      'measurementType': 'estimatedDbC',
      'frequencyWeighting': 'c',
      'timeResponse': 'slow',
    });
    await db.close();

    final service = DatabaseService(databasePathOverride: path);
    final row = (await service.getSessions()).single;
    expect(row.frequencyWeighting, FrequencyWeighting.c);
    expect(row.timeResponse, TimeResponse.slow);
    expect(row.statsDurationSeconds, 90);
    expect(await (await service.database).getVersion(), 6);
    await service.close();
  });

  test(
    'database open errors are reported rather than treated as empty history',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'sound-db-error-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final service = DatabaseService(databasePathOverride: directory.path);
      await expectLater(service.getSessions(), throwsA(isA<Exception>()));
    },
  );
}
