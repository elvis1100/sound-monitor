import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sound_level_monitor/controllers/monitor_controller.dart';
import 'package:sound_level_monitor/models/measurement_settings.dart';
import 'package:sound_level_monitor/services/audio_service.dart';
import 'package:sound_level_monitor/services/database_service.dart';
import 'package:sound_level_monitor/services/recording_writer.dart';

import 'fake_recording_writer.dart';
import 'monitor_controller_test.dart'
    show FakeAudioService, FakeDatabaseService, tone;

void main() {
  test(
    'automatic recording retains all audio and timeline units through pause and settings changes',
    () async {
      final directory = await Directory.systemTemp.createTemp('sound-capture-');
      final writer = WavRecordingWriter(directoryOverride: directory.path);
      final audio = FakeAudioService();
      final database = FakeDatabaseService();
      final container = ProviderContainer(
        overrides: [
          audioServiceProvider.overrideWithValue(audio),
          recordingWriterProvider.overrideWithValue(writer),
          databaseServiceProvider.overrideWithValue(database),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await audio.dispose();
        await directory.delete(recursive: true);
      });
      final controller = container.read(monitorControllerProvider.notifier);
      final expected = BytesBuilder();
      await controller.start();
      for (var index = 0; index < 8; index++) {
        final pcm = tone();
        expected.add(pcm);
        audio.stream.add(pcm);
      }
      await controller.pause();
      final pausedCount = writer.sampleCount;
      audio.stream.add(tone());
      expect(writer.sampleCount, pausedCount);
      await controller.start();
      for (var index = 0; index < 8; index++) {
        final pcm = tone(amplitude: 0.2);
        expected.add(pcm);
        audio.stream.add(pcm);
      }
      await controller.setMeasurementSettings(
        frequencyWeighting: FrequencyWeighting.c,
      );
      for (var index = 0; index < 8; index++) {
        final pcm = tone(amplitude: 0.05);
        expected.add(pcm);
        audio.stream.add(pcm);
      }
      await controller.save();
      final session = database.savedSessions.single;
      expect(
        (await File(session.audioFilePath!).readAsBytes()).sublist(44),
        expected.toBytes(),
      );
      expect(
        session.audioDurationMilliseconds,
        (expected.length * 1000 / 88200).round(),
      );
      expect(session.audioSampleRate, 44100);
      expect(session.recordingTimeline.first.milliseconds, 0);
      expect(
        session.recordingTimeline.last.milliseconds,
        session.audioDurationMilliseconds,
      );
      expect(
        session.recordingTimeline.any(
          (point) =>
              point.weighting == FrequencyWeighting.a && point.db != null,
        ),
        isTrue,
      );
      expect(
        session.recordingTimeline.any(
          (point) =>
              point.weighting == FrequencyWeighting.c && point.db != null,
        ),
        isTrue,
      );
      final firstC = session.recordingTimeline.indexWhere(
        (point) => point.weighting == FrequencyWeighting.c && point.db != null,
      );
      expect(session.recordingTimeline[firstC - 1].db, isNull);
      container.dispose();
      expect(await File(session.audioFilePath!).exists(), isTrue);
    },
  );

  test(
    'silence recordings save audio without claiming zero dB statistics',
    () async {
      final audio = FakeAudioService();
      final database = FakeDatabaseService();
      final writer = FakeRecordingWriter();
      final container = ProviderContainer(
        overrides: [
          audioServiceProvider.overrideWithValue(audio),
          recordingWriterProvider.overrideWithValue(writer),
          databaseServiceProvider.overrideWithValue(database),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await audio.dispose();
      });
      final controller = container.read(monitorControllerProvider.notifier);
      await controller.start();
      for (var index = 0; index < 25; index++) {
        audio.stream.add(Uint8List(4096));
      }
      expect(container.read(monitorControllerProvider).hasSamples, isFalse);
      await controller.save();
      final saved = database.savedSessions.single;
      expect(saved.hasLevelSamples, isFalse);
      expect(saved.audioDurationMilliseconds, greaterThan(1000));
      expect(
        saved.recordingTimeline.every((point) => point.db == null),
        isTrue,
      );
    },
  );

  test(
    'audio finalization and database failures preserve retryable recording',
    () async {
      final audio = FakeAudioService();
      final database = FakeDatabaseService();
      final writer = FakeRecordingWriter()..failFinish = true;
      final container = ProviderContainer(
        overrides: [
          audioServiceProvider.overrideWithValue(audio),
          recordingWriterProvider.overrideWithValue(writer),
          databaseServiceProvider.overrideWithValue(database),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await audio.dispose();
      });
      final controller = container.read(monitorControllerProvider.notifier);
      await controller.start();
      audio.stream.add(tone());
      await controller.save();
      expect(database.savedSessions, isEmpty);
      expect(
        container.read(monitorControllerProvider).phase,
        MonitorPhase.paused,
      );
      expect(writer.sampleCount, greaterThan(0));
      writer.failFinish = false;
      database.failInsert = true;
      await controller.save();
      expect(container.read(monitorControllerProvider).pendingSave, isTrue);
      expect(writer.retained, isTrue);
      final count = writer.sampleCount;
      database.failInsert = false;
      await controller.retrySave();
      expect(database.savedSessions, hasLength(1));
      expect(
        database.savedSessions.single.audioDurationMilliseconds,
        (count * 1000 / 44100).round(),
      );
    },
  );
}
