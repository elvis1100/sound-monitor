import 'package:flutter_test/flutter_test.dart';
import 'package:sound_level_monitor/models/session_model.dart';

void main() {
  group('SessionModel Tests', () {
    test('SessionModel serialization with null audioFilePath', () {
      final now = DateTime.now();
      final session = SessionModel(
        id: 1,
        title: 'Test Session',
        date: now,
        minDb: 35.5,
        avgDb: 55.2,
        maxDb: 80.1,
        audioFilePath: null,
        durationSeconds: 120,
        statsDurationSeconds: 45,
      );

      final map = session.toMap();
      expect(map['id'], 1);
      expect(map['title'], 'Test Session');
      expect(map['audioFilePath'], isNull);
      expect(map['minDb'], 35.5);
      expect(map['avgDb'], 55.2);
      expect(map['maxDb'], 80.1);
      expect(map['durationSeconds'], 120);
      expect(map['statsDurationSeconds'], 45);

      final deserialized = SessionModel.fromMap(map);
      expect(deserialized.id, 1);
      expect(deserialized.title, 'Test Session');
      expect(deserialized.audioFilePath, isNull);
      expect(deserialized.minDb, 35.5);
      expect(deserialized.avgDb, 55.2);
      expect(deserialized.maxDb, 80.1);
      expect(deserialized.durationSeconds, 120);
      expect(deserialized.statsDurationSeconds, 45);
    });

    test(
      'SessionModel backward compatibility with legacy audioFilePath string',
      () {
        final now = DateTime.now();
        final map = {
          'id': 2,
          'title': 'Legacy Session',
          'date': now.toIso8601String(),
          'minDb': 40,
          'avgDb': 60,
          'maxDb': 90,
          'audioFilePath': '/legacy/path/recording.pcm',
          'durationSeconds': 60,
        };

        final deserialized = SessionModel.fromMap(map);
        expect(deserialized.id, 2);
        expect(deserialized.title, 'Legacy Session');
        expect(deserialized.audioFilePath, '/legacy/path/recording.pcm');
        expect(deserialized.minDb, 40.0);
        expect(deserialized.avgDb, 60.0);
        expect(deserialized.maxDb, 90.0);
        expect(deserialized.statsDurationSeconds, 60);
      },
    );
  });
}
