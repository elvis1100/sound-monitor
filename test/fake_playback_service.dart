import 'dart:async';

import 'package:sound_level_monitor/models/measurement_settings.dart';
import 'package:sound_level_monitor/models/recording_point.dart';
import 'package:sound_level_monitor/models/session_model.dart';
import 'package:sound_level_monitor/services/database_service.dart';
import 'package:sound_level_monitor/services/playback_service.dart';

SessionModel sampleRecording() => SessionModel(
  id: 11,
  title: 'Sample recording',
  date: DateTime(2026, 10, 1, 12, 7),
  minDb: 48.6,
  avgDb: 63.4,
  maxDb: 93.6,
  durationSeconds: 20,
  frequencyWeighting: FrequencyWeighting.c,
  timeResponse: TimeResponse.slow,
  audioFilePath: '/test/recordings/sample.wav',
  audioDurationMilliseconds: 20000,
  audioSampleRate: 44100,
  recordingTimeline: const [
    RecordingPoint(
      milliseconds: 0,
      db: 48.6,
      weighting: FrequencyWeighting.a,
      response: TimeResponse.fast,
    ),
    RecordingPoint(
      milliseconds: 1000,
      db: null,
      weighting: FrequencyWeighting.c,
      response: TimeResponse.slow,
    ),
    RecordingPoint(
      milliseconds: 1000,
      db: 63.4,
      weighting: FrequencyWeighting.c,
      response: TimeResponse.slow,
    ),
    RecordingPoint(
      milliseconds: 19000,
      db: 93.6,
      weighting: FrequencyWeighting.c,
      response: TimeResponse.slow,
    ),
    RecordingPoint(
      milliseconds: 20000,
      db: 93.6,
      weighting: FrequencyWeighting.c,
      response: TimeResponse.slow,
    ),
  ],
);

class RecordingTestDatabase extends DatabaseService {
  SessionModel? saved = sampleRecording();
  bool failRename = false;
  bool failDelete = false;
  final List<String>? calls;

  RecordingTestDatabase({this.calls});
  @override
  Future<SessionModel?> getSession(int id) async => saved;
  @override
  Future<List<SessionModel>> getSessions({
    int limit = 50,
    int offset = 0,
  }) async => saved == null || offset > 0 ? [] : [saved!];
  @override
  Future<bool> renameSession(int id, String title) async {
    if (failRename) throw StateError('private path error');
    saved = saved!.withTitle(title.trim());
    return true;
  }

  @override
  Future<bool> deleteSession(int id) async {
    calls?.add('delete');
    if (failDelete) throw StateError('private path error');
    saved = null;
    return true;
  }
}

class FakePlaybackService implements PlaybackService {
  final stream = StreamController<PlaybackSnapshot>.broadcast(sync: true);
  PlaybackSnapshot snapshot = const PlaybackSnapshot(
    durationMilliseconds: 20000,
  );
  bool failOpen = false;
  bool failExport = false;
  bool exportResult = true;
  Completer<bool>? exportGate;
  final seekTargets = <int>[];
  final exports = <(String, String)>[];
  final shares = <(String, String)>[];
  final List<String>? calls;

  FakePlaybackService({this.calls});
  @override
  Stream<PlaybackSnapshot> get events => stream.stream;
  void emit(PlaybackSnapshot value) {
    snapshot = value;
    stream.add(value);
  }

  @override
  Future<PlaybackSnapshot> open(String path) async {
    if (failOpen) throw StateError('secret filesystem path');
    snapshot = const PlaybackSnapshot(durationMilliseconds: 20000);
    return snapshot;
  }

  @override
  Future<PlaybackSnapshot> play() async {
    emit(
      PlaybackSnapshot(
        positionMilliseconds: snapshot.positionMilliseconds >= 20000
            ? 0
            : snapshot.positionMilliseconds,
        durationMilliseconds: 20000,
        playing: true,
      ),
    );
    return snapshot;
  }

  @override
  Future<PlaybackSnapshot> pause() async {
    emit(
      PlaybackSnapshot(
        positionMilliseconds: snapshot.positionMilliseconds,
        durationMilliseconds: snapshot.durationMilliseconds,
      ),
    );
    return snapshot;
  }

  @override
  Future<void> seek(int milliseconds) async {
    seekTargets.add(milliseconds);
    emit(
      PlaybackSnapshot(
        positionMilliseconds: milliseconds,
        durationMilliseconds: 20000,
        playing: snapshot.playing,
      ),
    );
  }

  @override
  Future<void> close() async {
    calls?.add('close');
    snapshot = const PlaybackSnapshot(durationMilliseconds: 20000);
  }

  @override
  Future<bool> export(String path, String title) async {
    exports.add((path, title));
    if (failExport) throw StateError('secret filesystem path');
    return exportGate == null ? exportResult : await exportGate!.future;
  }

  @override
  Future<void> share(String path, String title) async {
    shares.add((path, title));
  }
}
