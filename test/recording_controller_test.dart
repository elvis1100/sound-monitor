import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sound_level_monitor/controllers/recording_controller.dart';
import 'package:sound_level_monitor/models/measurement_settings.dart';
import 'package:sound_level_monitor/models/recording_point.dart';
import 'package:sound_level_monitor/services/database_service.dart';
import 'package:sound_level_monitor/services/playback_service.dart';
import 'package:sound_level_monitor/views/recording/widgets/recording_timeline_chart.dart';

import 'fake_playback_service.dart';

void main() {
  test(
    'playback, seeking, and completion use the original timeline units',
    () async {
      final player = FakePlaybackService();
      final database = RecordingTestDatabase();
      final container = ProviderContainer(
        overrides: [
          databaseServiceProvider.overrideWithValue(database),
          playbackServiceProvider.overrideWithValue(player),
        ],
      );
      container.listen(recordingControllerProvider(11), (_, _) {});
      addTearDown(() async {
        container.dispose();
        await player.stream.close();
      });
      final controller = container.read(
        recordingControllerProvider(11).notifier,
      );
      await controller.load();
      expect(container.read(recordingControllerProvider(11)).point!.db, 48.6);
      expect(
        container.read(recordingControllerProvider(11)).point!.weighting,
        FrequencyWeighting.a,
      );
      await controller.togglePlayback();
      expect(
        container.read(recordingControllerProvider(11)).playback.playing,
        isTrue,
      );
      await controller.seek(1500);
      expect(container.read(recordingControllerProvider(11)).point!.db, 63.4);
      expect(
        container.read(recordingControllerProvider(11)).point!.weighting,
        FrequencyWeighting.c,
      );
      await controller.seek(-5000);
      await controller.seek(999999);
      expect(player.seekTargets, [1500, 0, 20000]);
      player.emit(
        const PlaybackSnapshot(
          positionMilliseconds: 20000,
          durationMilliseconds: 20000,
        ),
      );
      expect(
        container.read(recordingControllerProvider(11)).playback.playing,
        isFalse,
      );
      await controller.togglePlayback();
      expect(
        container
            .read(recordingControllerProvider(11))
            .playback
            .positionMilliseconds,
        0,
      );
    },
  );

  test(
    'rename/export/share preserve the file and delete closes playback first',
    () async {
      final calls = <String>[];
      final player = FakePlaybackService(calls: calls);
      final database = RecordingTestDatabase(calls: calls);
      final container = ProviderContainer(
        overrides: [
          databaseServiceProvider.overrideWithValue(database),
          playbackServiceProvider.overrideWithValue(player),
        ],
      );
      container.listen(recordingControllerProvider(11), (_, _) {});
      addTearDown(() async {
        container.dispose();
        await player.stream.close();
      });
      final controller = container.read(
        recordingControllerProvider(11).notifier,
      );
      await controller.load();
      await controller.togglePlayback();
      expect(await controller.rename('Changed name'), isTrue);
      expect(
        container.read(recordingControllerProvider(11)).playback.playing,
        isTrue,
      );
      expect(
        container
            .read(recordingControllerProvider(11))
            .session!
            .recordingTimeline,
        hasLength(5),
      );
      expect(await controller.exportAudio(), isTrue);
      expect(player.exports.single, (
        '/test/recordings/sample.wav',
        'Changed name',
      ));
      await controller.shareAudio();
      expect(player.shares.single.$2, 'Changed name');
      calls.clear();
      expect(await controller.delete(), isTrue);
      expect(calls, ['close', 'delete']);
    },
  );

  test(
    'load/export failures are safe and export cancellation is not an error',
    () async {
      final player = FakePlaybackService()..failOpen = true;
      final database = RecordingTestDatabase();
      final container = ProviderContainer(
        overrides: [
          databaseServiceProvider.overrideWithValue(database),
          playbackServiceProvider.overrideWithValue(player),
        ],
      );
      container.listen(recordingControllerProvider(11), (_, _) {});
      addTearDown(() async {
        container.dispose();
        await player.stream.close();
      });
      final controller = container.read(
        recordingControllerProvider(11).notifier,
      );
      await controller.load();
      expect(container.read(recordingControllerProvider(11)).ready, isFalse);
      expect(
        container.read(recordingControllerProvider(11)).error,
        isNot(contains('secret')),
      );
      player.failOpen = false;
      await controller.load();
      player.failExport = true;
      expect(await controller.exportAudio(), isNull);
      expect(container.read(recordingControllerProvider(11)).busy, isFalse);
      player.failExport = false;
      player.exportResult = false;
      expect(await controller.exportAudio(), isFalse);
      expect(container.read(recordingControllerProvider(11)).error, isNull);
      player.exportGate = Completer<bool>();
      final exporting = controller.exportAudio();
      await Future<void>.delayed(Duration.zero);
      expect(container.read(recordingControllerProvider(11)).busy, isTrue);
      final exportsBefore = player.exports.length;
      await controller.shareAudio();
      await controller.exportAudio();
      expect(player.shares, isEmpty);
      expect(player.exports.length, exportsBefore);
      player.exportGate!.complete(true);
      expect(await exporting, isTrue);
    },
  );

  test(
    'downsampling preserves peaks, bounds work, and never bridges missing readings',
    () {
      final points = List.generate(
        6000,
        (index) => RecordingPoint(
          milliseconds: index * 100,
          db: index == 1234
              ? 139
              : index.isOdd
              ? null
              : 50,
          weighting: FrequencyWeighting.a,
          response: TimeResponse.fast,
        ),
      );
      final display = recordingDisplayPoints(points);
      expect(display.length, lessThanOrEqualTo(3000));
      expect(display.any((point) => point.db == 139), isTrue);
      for (var index = 1; index < display.length; index++) {
        final before = display[index - 1];
        final after = display[index];
        if (before.db != null && after.db != null) {
          final start = before.milliseconds ~/ 100;
          final end = after.milliseconds ~/ 100;
          expect(
            points.sublist(start + 1, end).any((point) => point.db == null),
            isFalse,
          );
        }
      }
    },
  );
}
