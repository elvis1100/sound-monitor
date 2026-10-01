import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sound_level_monitor/models/measurement_settings.dart';
import 'package:sound_level_monitor/models/recording_point.dart';
import 'package:sound_level_monitor/models/session_model.dart';
import 'package:sound_level_monitor/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

SessionModel session(int id, String path) => SessionModel(
  id: id,
  title: 'Recording $id',
  date: DateTime.utc(2026, 10, 1),
  minDb: 40,
  avgDb: 60,
  maxDb: 80,
  durationSeconds: 10,
  audioFilePath: path,
  audioSampleRate: 44100,
  audioDurationMilliseconds: 10012,
  recordingTimeline: const [
    RecordingPoint(
      milliseconds: 0,
      db: 40,
      weighting: FrequencyWeighting.a,
      response: TimeResponse.fast,
    ),
    RecordingPoint(
      milliseconds: 5000,
      db: null,
      weighting: FrequencyWeighting.c,
      response: TimeResponse.fast,
    ),
    RecordingPoint(
      milliseconds: 10000,
      db: 80,
      weighting: FrequencyWeighting.c,
      response: TimeResponse.slow,
    ),
  ],
);

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  test(
    'recording metadata persists, summaries stay small, and rename preserves timeline',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'sound-recording-db-',
      );
      final database = DatabaseService(
        databasePathOverride: '${directory.path}/sessions.db',
        recordingsDirectoryOverride: '${directory.path}/recordings',
      );
      addTearDown(() async {
        await database.close();
        await directory.delete(recursive: true);
      });
      await database.insertSession(
        session(1, '${directory.path}/recordings/one.wav'),
      );
      expect((await database.getSessions()).single.recordingTimeline, isEmpty);
      expect(await database.renameSession(1, '  New name  '), isTrue);
      expect(await database.renameSession(1, '   '), isFalse);
      await database.close();
      final saved = (await database.getSession(1))!;
      expect(saved.title, 'New name');
      expect(saved.audioDurationMilliseconds, 10012);
      expect(saved.audioSampleRate, 44100);
      expect(saved.recordingTimeline, hasLength(3));
      expect(saved.recordingTimeline[1].db, isNull);
      expect(saved.recordingTimeline.last.weighting, FrequencyWeighting.c);
    },
  );

  test(
    'failed metadata deletion retains audio; committed deletion removes only owned files',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'sound-audio-delete-',
      );
      final root = await Directory('${directory.path}/recordings').create();
      final database = DatabaseService(
        databasePathOverride: '${directory.path}/sessions.db',
        recordingsDirectoryOverride: root.path,
      );
      addTearDown(() async {
        await database.close();
        await directory.delete(recursive: true);
      });
      final owned = await File('${root.path}/one.wav').writeAsBytes([1, 2]);
      final outside = await File(
        '${directory.path}/outside.wav',
      ).writeAsBytes([3, 4]);
      await database.insertSession(session(1, owned.path));
      await database.insertSession(session(2, outside.path));
      final db = await database.database;
      await db.execute(
        "CREATE TRIGGER fail_delete BEFORE DELETE ON sessions BEGIN SELECT RAISE(ABORT, 'test failure'); END",
      );
      await expectLater(database.deleteSession(1), throwsA(isA<Exception>()));
      expect(await owned.exists(), isTrue);
      expect(await database.getSession(1), isNotNull);
      await db.execute('DROP TRIGGER fail_delete');
      expect(await database.deleteSession(1), isTrue);
      expect(await owned.exists(), isFalse);
      await database.clearAllSessions();
      expect(await database.getSessions(), isEmpty);
      expect(await outside.exists(), isTrue);
    },
  );

  test(
    'audio cleanup never follows a link outside the recording directory',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'sound-audio-link-',
      );
      final root = await Directory('${directory.path}/recordings').create();
      final outside = await File(
        '${directory.path}/outside.wav',
      ).writeAsBytes([1, 2]);
      final link = await Link('${root.path}/linked.wav').create(outside.path);
      final database = DatabaseService(
        databasePathOverride: '${directory.path}/sessions.db',
        recordingsDirectoryOverride: root.path,
      );
      addTearDown(() async {
        await database.close();
        await directory.delete(recursive: true);
      });
      await database.insertSession(session(1, link.path));
      expect(await database.deleteSession(1), isTrue);
      expect(await outside.exists(), isTrue);
    },
  );
}
