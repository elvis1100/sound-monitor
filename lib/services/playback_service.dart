import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final playbackServiceProvider = Provider.autoDispose<PlaybackService>((ref) {
  final service = AndroidPlaybackService();
  ref.onDispose(() => unawaited(service.close()));
  return service;
});

class PlaybackSnapshot {
  final int positionMilliseconds;
  final int durationMilliseconds;
  final bool playing;
  final String? error;

  const PlaybackSnapshot({
    this.positionMilliseconds = 0,
    this.durationMilliseconds = 0,
    this.playing = false,
    this.error,
  });

  factory PlaybackSnapshot.fromMap(Map<dynamic, dynamic> map) =>
      PlaybackSnapshot(
        positionMilliseconds: (map['positionMs'] as num?)?.toInt() ?? 0,
        durationMilliseconds: (map['durationMs'] as num?)?.toInt() ?? 0,
        playing: map['playing'] == true,
        error: map['error'] as String?,
      );
}

/// One foreground local-file player. Position/duration/seek are milliseconds.
/// Platform failures propagate; controllers translate them into user messages.
/// Export opens the system destination picker; share opens the system share sheet.
abstract class PlaybackService {
  Stream<PlaybackSnapshot> get events;
  Future<PlaybackSnapshot> open(String path);
  Future<PlaybackSnapshot> play();
  Future<PlaybackSnapshot> pause();
  Future<void> seek(int milliseconds);
  Future<void> close();
  Future<bool> export(String path, String title);
  Future<void> share(String path, String title);
}

class AndroidPlaybackService implements PlaybackService {
  static const _methods = MethodChannel('sound_monitor/recordings');
  static const _eventChannel = EventChannel('sound_monitor/playback');
  late final Stream<PlaybackSnapshot> _events = _eventChannel
      .receiveBroadcastStream()
      .map((event) => PlaybackSnapshot.fromMap(event as Map));

  @override
  Stream<PlaybackSnapshot> get events => _events;

  Future<PlaybackSnapshot> _snapshot(
    String method, [
    Map<String, Object?>? args,
  ]) async => PlaybackSnapshot.fromMap(
    await _methods.invokeMapMethod(method, args) ?? {},
  );

  @override
  Future<PlaybackSnapshot> open(String path) =>
      _snapshot('open', {'path': path});
  @override
  Future<PlaybackSnapshot> play() => _snapshot('play');
  @override
  Future<PlaybackSnapshot> pause() => _snapshot('pause');
  @override
  Future<void> seek(int milliseconds) =>
      _methods.invokeMethod('seek', {'milliseconds': milliseconds});
  @override
  Future<void> close() async {
    try {
      await _methods.invokeMethod<void>('close');
    } catch (_) {
      // Disposal must also work after the activity or channel has gone away.
    }
  }

  @override
  Future<bool> export(String path, String title) async =>
      await _methods.invokeMethod<bool>('export', {
        'path': path,
        'title': title,
      }) ??
      false;
  @override
  Future<void> share(String path, String title) =>
      _methods.invokeMethod('share', {'path': path, 'title': title});
}
