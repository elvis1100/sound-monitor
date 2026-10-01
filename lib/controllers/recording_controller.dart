import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/recording_point.dart';
import '../models/session_model.dart';
import '../services/database_service.dart';
import '../services/playback_service.dart';

const _unchanged = Object();

class RecordingState {
  final SessionModel? session;
  final PlaybackSnapshot playback;
  final bool loading;
  final bool ready;
  final bool busy;
  final String? error;

  const RecordingState({
    this.session,
    this.playback = const PlaybackSnapshot(),
    this.loading = true,
    this.ready = false,
    this.busy = false,
    this.error,
  });

  int get durationMilliseconds => playback.durationMilliseconds > 0
      ? playback.durationMilliseconds
      : session?.audioDurationMilliseconds ??
            (session?.durationSeconds ?? 0) * 1000;

  /// Find the sample at the playhead without scanning a long timeline each tick.
  RecordingPoint? get point {
    final points = session?.recordingTimeline;
    if (points == null || points.isEmpty) return null;
    var low = 0;
    var high = points.length - 1;
    var index = -1;
    while (low <= high) {
      final middle = (low + high) ~/ 2;
      if (points[middle].milliseconds <= playback.positionMilliseconds) {
        index = middle;
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    return index < 0 ? null : points[index];
  }

  RecordingState copyWith({
    SessionModel? session,
    PlaybackSnapshot? playback,
    bool? loading,
    bool? ready,
    bool? busy,
    Object? error = _unchanged,
  }) => RecordingState(
    session: session ?? this.session,
    playback: playback ?? this.playback,
    loading: loading ?? this.loading,
    ready: ready ?? this.ready,
    busy: busy ?? this.busy,
    error: identical(error, _unchanged) ? this.error : error as String?,
  );
}

final recordingControllerProvider = NotifierProvider.autoDispose
    .family<RecordingController, RecordingState, int>(RecordingController.new);

class RecordingController extends Notifier<RecordingState> {
  final int sessionId;
  late DatabaseService _database;
  late PlaybackService _player;
  StreamSubscription<PlaybackSnapshot>? _subscription;
  bool _disposed = false;
  int _generation = 0;

  RecordingController(this.sessionId);

  @override
  RecordingState build() {
    _database = ref.read(databaseServiceProvider);
    _player = ref.watch(playbackServiceProvider);
    _subscription = _player.events.listen(
      (event) {
        if (!_disposed) {
          state = state.copyWith(
            playback: event,
            error: event.error == null
                ? _unchanged
                : 'Could not play this recording. Tap Retry.',
            ready: event.error == null ? state.ready : false,
          );
        }
      },
      onError: (Object _) {
        if (!_disposed) {
          state = state.copyWith(
            ready: false,
            error: 'Could not play this recording. Tap Retry.',
          );
        }
      },
    );
    ref.onDispose(() {
      _disposed = true;
      _generation++;
      unawaited(_subscription?.cancel());
    });
    return const RecordingState();
  }

  Future<void> load() async {
    final generation = ++_generation;
    state = state.copyWith(loading: true, ready: false, error: null);
    try {
      await _player.close();
      final session = await _database.getSession(sessionId);
      if (_disposed || generation != _generation) return;
      if (session == null) {
        state = state.copyWith(
          loading: false,
          error: 'This session is no longer available.',
        );
        return;
      }
      state = state.copyWith(session: session);
      final path = session.audioFilePath;
      if (path == null || !path.toLowerCase().endsWith('.wav')) {
        state = state.copyWith(
          loading: false,
          error: 'This older session has no playable audio.',
        );
        return;
      }
      final playback = await _player.open(path);
      if (_disposed || generation != _generation) return;
      state = state.copyWith(playback: playback, loading: false, ready: true);
    } catch (_) {
      if (!_disposed && generation == _generation) {
        state = state.copyWith(
          loading: false,
          ready: false,
          error: 'Could not open this recording. Tap Retry.',
        );
      }
    }
  }

  Future<void> togglePlayback() async {
    if (!state.ready || state.busy) return;
    try {
      final snapshot = state.playback.playing
          ? await _player.pause()
          : await _player.play();
      if (!_disposed) state = state.copyWith(playback: snapshot, error: null);
    } catch (_) {
      _actionError('Could not play this recording. Tap Retry.');
    }
  }

  Future<void> pause() async {
    if (!state.ready) return;
    try {
      final playback = await _player.pause();
      if (!_disposed) state = state.copyWith(playback: playback);
    } catch (_) {
      _actionError('Could not pause playback.');
    }
  }

  Future<void> seek(int milliseconds) async {
    if (!state.ready || state.busy) return;
    final target = milliseconds.clamp(0, state.durationMilliseconds);
    try {
      await _player.seek(target);
      if (!_disposed) {
        state = state.copyWith(
          playback: PlaybackSnapshot(
            positionMilliseconds: target,
            durationMilliseconds: state.durationMilliseconds,
            playing: state.playback.playing,
          ),
        );
      }
    } catch (_) {
      _actionError('Could not seek in this recording.');
    }
  }

  Future<bool> rename(String title) async {
    if (state.busy || state.session == null) return false;
    state = state.copyWith(busy: true);
    try {
      final success = await _database.renameSession(sessionId, title);
      if (_disposed) return false;
      if (success) {
        state = state.copyWith(
          session: state.session!.withTitle(title.trim()),
          error: null,
        );
      } else {
        _actionError('Could not rename this session. Use 1–100 characters.');
      }
      return success;
    } catch (_) {
      _actionError('Could not rename this session. Try again.');
      return false;
    } finally {
      if (!_disposed) state = state.copyWith(busy: false);
    }
  }

  Future<bool> delete() async {
    if (state.busy || state.session == null) return false;
    state = state.copyWith(busy: true);
    try {
      await _player.close();
      if (!_disposed) state = state.copyWith(ready: false);
      final success = await _database.deleteSession(sessionId);
      if (!success) _actionError('Could not delete this session. Try again.');
      return success;
    } catch (_) {
      _actionError('Could not delete this session. Try again.');
      return false;
    } finally {
      if (!_disposed) state = state.copyWith(busy: false);
    }
  }

  Future<bool?> exportAudio() async {
    if (!state.ready || state.busy) return null;
    state = state.copyWith(busy: true, error: null);
    try {
      await pause();
      return await _player.export(
        state.session!.audioFilePath!,
        state.session!.title,
      );
    } catch (_) {
      _actionError(
        'Could not save audio. Choose another location and try again.',
      );
      return null;
    } finally {
      if (!_disposed) state = state.copyWith(busy: false);
    }
  }

  Future<void> shareAudio() async {
    if (!state.ready || state.busy) return;
    state = state.copyWith(busy: true, error: null);
    try {
      await pause();
      await _player.share(state.session!.audioFilePath!, state.session!.title);
    } catch (_) {
      _actionError('Could not open sharing. Try again.');
    } finally {
      if (!_disposed) state = state.copyWith(busy: false);
    }
  }

  void _actionError(String message) {
    if (!_disposed) state = state.copyWith(error: message);
  }
}
