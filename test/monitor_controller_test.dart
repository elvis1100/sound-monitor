import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'fake_recording_writer.dart';
import 'package:sound_level_monitor/services/recording_writer.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sound_level_monitor/controllers/monitor_controller.dart';
import 'package:sound_level_monitor/models/calibration_profile.dart';
import 'package:sound_level_monitor/models/measurement_settings.dart';
import 'package:sound_level_monitor/models/session_model.dart';
import 'package:sound_level_monitor/services/audio_level_processor.dart';
import 'package:sound_level_monitor/services/audio_service.dart';
import 'package:sound_level_monitor/services/database_service.dart';

class FakeAudioService implements AudioService {
  final stream = StreamController<Uint8List>.broadcast(sync: true);
  Completer<void>? startGate;
  int stopCalls = 0;
  int startCalls = 0;

  @override
  Future<PermissionStatus> requestPermission() async =>
      PermissionStatus.granted;

  @override
  Future<AudioInputSession> start({
    void Function(int sampleRate)? onSampleRateChanged,
  }) async {
    await startGate?.future;
    startCalls++;
    return AudioInputSession(
      pcm: stream.stream,
      sampleRate: 44100,
      inputKey: CalibrationProfile.builtInInputKey,
    );
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }

  @override
  Future<void> dispose() => stream.close();
}

class FakeDatabaseService extends DatabaseService {
  bool failInsert = false;
  CalibrationProfile? profile;
  final savedSessions = <SessionModel>[];

  @override
  Future<CalibrationProfile?> getCalibration(String inputKey) async =>
      profile?.inputKey == inputKey ? profile : null;

  @override
  Future<void> saveCalibration(CalibrationProfile value) async {
    profile = value;
  }

  @override
  Future<void> clearCalibration(String inputKey) async {
    profile = null;
  }

  @override
  Future<int> insertSession(SessionModel session) async {
    if (failInsert) throw StateError('Storage unavailable');
    savedSessions.removeWhere((saved) => saved.id == session.id);
    savedSessions.add(session);
    return session.id!;
  }
}

Uint8List tone({double amplitude = 0.1}) {
  final bytes = Uint8List(AudioLevelProcessor.windowSize * 2);
  final data = ByteData.sublistView(bytes);
  for (var index = 0; index < AudioLevelProcessor.windowSize; index++) {
    data.setInt16(
      index * 2,
      (32767 * amplitude * sin(2 * pi * 1000 * index / 44100)).round(),
      Endian.little,
    );
  }
  return bytes;
}

void main() {
  test('spectrum peaks hold through lower sound, silence, and pause', () async {
    final audio = FakeAudioService();
    final container = ProviderContainer(
      overrides: [
        audioServiceProvider.overrideWithValue(audio),
        recordingWriterProvider.overrideWithValue(FakeRecordingWriter()),
        databaseServiceProvider.overrideWithValue(FakeDatabaseService()),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await audio.dispose();
    });
    final controller = container.read(monitorControllerProvider.notifier);
    await controller.start();
    for (var index = 0; index < 20; index++) {
      audio.stream.add(tone(amplitude: 0.2));
    }
    final high = container.read(monitorControllerProvider).spectrumPeaks;
    expect(high, hasLength(31));
    expect(() => high[17] = 0, throwsUnsupportedError);
    for (var index = 0; index < 20; index++) {
      audio.stream.add(tone(amplitude: 0.01));
    }
    final lower = container.read(monitorControllerProvider);
    expect(lower.spectrumPeaks[17], greaterThan(lower.spectrum[17] + 15));
    for (var index = 0; index < 31; index++) {
      expect(lower.spectrumPeaks[index], greaterThanOrEqualTo(high[index]));
    }
    for (var index = 0; index < 5; index++) {
      audio.stream.add(Uint8List(AudioLevelProcessor.windowSize * 2));
    }
    final gap = container.read(monitorControllerProvider);
    expect(gap.spectrum, isEmpty);
    expect(gap.spectrumPeaks, lower.spectrumPeaks);
    await controller.pause();
    expect(
      container.read(monitorControllerProvider).spectrumPeaks,
      gap.spectrumPeaks,
    );
    await controller.start();
    audio.stream.add(tone(amplitude: 0.01));
    expect(
      container.read(monitorControllerProvider).spectrumPeaks,
      gap.spectrumPeaks,
    );
    await controller.reset();
    expect(container.read(monitorControllerProvider).spectrumPeaks, isEmpty);
  });

  test('offset changes and a saved session clear spectrum peaks', () async {
    final audio = FakeAudioService();
    final container = ProviderContainer(
      overrides: [
        audioServiceProvider.overrideWithValue(audio),
        recordingWriterProvider.overrideWithValue(FakeRecordingWriter()),
        databaseServiceProvider.overrideWithValue(FakeDatabaseService()),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await audio.dispose();
    });
    final controller = container.read(monitorControllerProvider.notifier);
    await controller.start();
    for (var index = 0; index < 5; index++) {
      audio.stream.add(tone());
    }
    expect(container.read(monitorControllerProvider).spectrumPeaks, isNotEmpty);
    await controller.setManualAdjustment(3);
    expect(container.read(monitorControllerProvider).spectrumPeaks, isEmpty);
    for (var index = 0; index < 5; index++) {
      audio.stream.add(tone());
    }
    expect(container.read(monitorControllerProvider).spectrumPeaks, isNotEmpty);
    await controller.save();
    expect(container.read(monitorControllerProvider).spectrumPeaks, isEmpty);
  });

  test('stop queued during start still closes the recording', () async {
    final audio = FakeAudioService()..startGate = Completer<void>();
    final database = FakeDatabaseService();
    final container = ProviderContainer(
      overrides: [
        audioServiceProvider.overrideWithValue(audio),
        recordingWriterProvider.overrideWithValue(FakeRecordingWriter()),
        databaseServiceProvider.overrideWithValue(database),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await audio.dispose();
    });

    final controller = container.read(monitorControllerProvider.notifier);
    final starting = controller.start();
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(monitorControllerProvider).phase,
      MonitorPhase.starting,
    );
    final stopping = controller.stop();
    audio.startGate!.complete();
    await Future.wait([starting, stopping]);

    expect(container.read(monitorControllerProvider).phase, MonitorPhase.idle);
    expect(audio.stopCalls, 1);
  });

  test(
    'failed session save remains retryable and blocks a new session',
    () async {
      final audio = FakeAudioService();
      final database = FakeDatabaseService()..failInsert = true;
      final container = ProviderContainer(
        overrides: [
          audioServiceProvider.overrideWithValue(audio),
          recordingWriterProvider.overrideWithValue(FakeRecordingWriter()),
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
      expect(container.read(monitorControllerProvider).pendingSave, isTrue);
      expect(
        container.read(monitorControllerProvider).errorMessage,
        contains('not saved'),
      );

      await controller.start();
      expect(container.read(monitorControllerProvider).isRecording, isFalse);
      database.failInsert = false;
      await controller.retrySave();
      expect(container.read(monitorControllerProvider).pendingSave, isFalse);
      expect(database.savedSessions, hasLength(1));
    },
  );

  test(
    'pause resumes the unsaved session and Save archives then pauses',
    () async {
      final audio = FakeAudioService();
      final database = FakeDatabaseService();
      final container = ProviderContainer(
        overrides: [
          audioServiceProvider.overrideWithValue(audio),
          recordingWriterProvider.overrideWithValue(FakeRecordingWriter()),
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
      await controller.pause();
      expect(
        container.read(monitorControllerProvider).phase,
        MonitorPhase.paused,
      );
      expect(database.savedSessions, isEmpty);
      await controller.start();
      audio.stream.add(tone());
      await controller.save();
      expect(database.savedSessions, hasLength(1));
      expect(
        container.read(monitorControllerProvider).phase,
        MonitorPhase.idle,
      );
      expect(container.read(monitorControllerProvider).hasSamples, isFalse);
    },
  );

  test(
    'settings changes keep capture and timer while resetting statistics',
    () async {
      final audio = FakeAudioService();
      final database = FakeDatabaseService();
      final container = ProviderContainer(
        overrides: [
          audioServiceProvider.overrideWithValue(audio),
          recordingWriterProvider.overrideWithValue(FakeRecordingWriter()),
          databaseServiceProvider.overrideWithValue(database),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await audio.dispose();
      });
      final controller = container.read(monitorControllerProvider.notifier);
      await controller.start();
      final pcm = tone();
      for (var index = 0; index < 50; index++) {
        audio.stream.add(pcm);
      }
      final before = container.read(monitorControllerProvider);
      expect(before.elapsedSeconds, greaterThanOrEqualTo(1));
      expect(before.hasSamples, isTrue);
      expect(before.spectrumPeaks, isNotEmpty);

      await controller.setMeasurementSettings(
        frequencyWeighting: FrequencyWeighting.c,
        timeResponse: TimeResponse.slow,
      );
      final changed = container.read(monitorControllerProvider);
      expect(changed.isRecording, isTrue);
      expect(changed.frequencyWeighting, FrequencyWeighting.c);
      expect(changed.timeResponse, TimeResponse.slow);
      expect(changed.hasSamples, isFalse);
      expect(changed.history, isEmpty);
      expect(changed.spectrumPeaks, isEmpty);
      expect(changed.elapsedSeconds, before.elapsedSeconds);
      expect(audio.startCalls, 1);
      expect(audio.stopCalls, 0);

      for (var index = 0; index < 50; index++) {
        audio.stream.add(pcm);
      }
      await controller.save();
      final saved = database.savedSessions.single;
      expect(saved.frequencyWeighting, FrequencyWeighting.c);
      expect(saved.timeResponse, TimeResponse.slow);
      expect(saved.measurementType, MeasurementType.estimatedDbC);
      expect(saved.durationSeconds, greaterThan(saved.statsDurationSeconds));
    },
  );

  test(
    'settings can change while paused without losing session time',
    () async {
      final audio = FakeAudioService();
      final database = FakeDatabaseService();
      final container = ProviderContainer(
        overrides: [
          audioServiceProvider.overrideWithValue(audio),
          recordingWriterProvider.overrideWithValue(FakeRecordingWriter()),
          databaseServiceProvider.overrideWithValue(database),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await audio.dispose();
      });
      final controller = container.read(monitorControllerProvider.notifier);
      await controller.start();
      final pcm = tone();
      for (var index = 0; index < 50; index++) {
        audio.stream.add(pcm);
      }
      await controller.pause();
      final elapsed = container.read(monitorControllerProvider).elapsedSeconds;
      await controller.setMeasurementSettings(timeResponse: TimeResponse.slow);
      final changed = container.read(monitorControllerProvider);
      expect(changed.phase, MonitorPhase.paused);
      expect(changed.hasSession, isTrue);
      expect(changed.hasSamples, isFalse);
      expect(changed.elapsedSeconds, elapsed);
      expect(changed.spectrumPeaks, isEmpty);
      await controller.start();
      for (var index = 0; index < 50; index++) {
        audio.stream.add(pcm);
      }
      await controller.save();
      expect(
        database.savedSessions.single.durationSeconds,
        greaterThan(elapsed),
      );
      expect(
        database.savedSessions.single.statsDurationSeconds,
        lessThan(database.savedSessions.single.durationSeconds),
      );
    },
  );

  test('digital silence on start or resume never becomes a zero MIN', () async {
    final audio = FakeAudioService();
    final database = FakeDatabaseService();
    final container = ProviderContainer(
      overrides: [
        audioServiceProvider.overrideWithValue(audio),
        recordingWriterProvider.overrideWithValue(FakeRecordingWriter()),
        databaseServiceProvider.overrideWithValue(database),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await audio.dispose();
    });
    final controller = container.read(monitorControllerProvider.notifier);
    final silence = Uint8List(AudioLevelProcessor.windowSize * 2);
    await controller.start();
    for (var index = 0; index < 5; index++) {
      audio.stream.add(silence);
    }
    audio.stream.add(tone(amplitude: 0.0001));
    expect(container.read(monitorControllerProvider).hasSamples, isFalse);
    expect(container.read(monitorControllerProvider).hasLiveReading, isFalse);
    audio.stream.add(tone());
    final minimum = container.read(monitorControllerProvider).minDb;
    expect(minimum, greaterThan(0));
    await controller.pause();
    await controller.start();
    for (var index = 0; index < 5; index++) {
      audio.stream.add(silence);
    }
    final interrupted = container.read(monitorControllerProvider);
    expect(interrupted.minDb, minimum);
    expect(interrupted.hasLiveReading, isFalse);
    expect(interrupted.history, contains(null));
    audio.stream.add(tone());
    await controller.save();
    expect(database.savedSessions.single.minDb, greaterThan(0));
  });

  test(
    'manual offset starts at zero and restarts stats without stopping capture',
    () async {
      final audio = FakeAudioService();
      final database = FakeDatabaseService();
      final container = ProviderContainer(
        overrides: [
          audioServiceProvider.overrideWithValue(audio),
          recordingWriterProvider.overrideWithValue(FakeRecordingWriter()),
          databaseServiceProvider.overrideWithValue(database),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await audio.dispose();
      });

      final controller = container.read(monitorControllerProvider.notifier);
      await controller.start();
      final pcm = tone();
      for (var index = 0; index < 5; index++) {
        audio.stream.add(pcm);
      }
      final before = container.read(monitorControllerProvider);
      expect(before.minDb, greaterThan(0));
      await controller.setManualAdjustment(3);
      final cleared = container.read(monitorControllerProvider);
      expect(database.profile?.source, CalibrationSource.manual);
      expect(database.profile?.adjustmentDb, 3);
      expect(cleared.hasSamples, isFalse);
      expect(cleared.elapsedSeconds, before.elapsedSeconds);
      expect(audio.stopCalls, 0);
      audio.stream.add(pcm);
      final adjusted = container.read(monitorControllerProvider);
      expect(adjusted.currentDb, closeTo(before.currentDb + 3, 0.2));
      expect(adjusted.minDb, greaterThan(0));
      await controller.save();
      expect(
        database.savedSessions.single.measurementType,
        MeasurementType.manualAdjustedDbA,
      );
    },
  );

  test('calibration rejects a changing reference sound', () async {
    final audio = FakeAudioService();
    final database = FakeDatabaseService();
    final container = ProviderContainer(
      overrides: [
        audioServiceProvider.overrideWithValue(audio),
        recordingWriterProvider.overrideWithValue(FakeRecordingWriter()),
        databaseServiceProvider.overrideWithValue(database),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await audio.dispose();
    });

    final controller = container.read(monitorControllerProvider.notifier);
    await controller.start();
    for (var index = 0; index < 11; index++) {
      audio.stream.add(tone(amplitude: 0.05));
    }
    for (var index = 0; index < 12; index++) {
      audio.stream.add(tone(amplitude: 0.2));
    }
    await controller.calibrate(72);
    expect(database.profile, isNull);
    expect(
      container.read(monitorControllerProvider).errorMessage,
      contains('steady'),
    );
    await controller.stop();
  });

  test(
    'reference calibration updates the live reading and saved session type',
    () async {
      final audio = FakeAudioService();
      final database = FakeDatabaseService();
      final container = ProviderContainer(
        overrides: [
          audioServiceProvider.overrideWithValue(audio),
          recordingWriterProvider.overrideWithValue(FakeRecordingWriter()),
          databaseServiceProvider.overrideWithValue(database),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await audio.dispose();
      });

      final controller = container.read(monitorControllerProvider.notifier);
      await controller.start();
      final pcm = tone();
      for (var index = 0; index < 23; index++) {
        audio.stream.add(pcm);
      }
      await controller.calibrate(72);
      expect(database.profile, isNotNull);
      audio.stream.add(pcm);
      expect(
        container.read(monitorControllerProvider).currentDb,
        closeTo(72, 0.2),
      );

      await controller.save();
      expect(
        database.savedSessions.single.measurementType,
        MeasurementType.referenceAdjustedDbA,
      );
    },
  );
}
