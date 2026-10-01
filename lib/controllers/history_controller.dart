import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/session_model.dart';
import '../services/database_service.dart';

const _unchanged = Object();

class HistoryState {
  final List<SessionModel> sessions;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final bool mutating;
  final String? error;
  final String? moreError;

  const HistoryState({
    this.sessions = const [],
    this.loading = true,
    this.loadingMore = false,
    this.hasMore = true,
    this.mutating = false,
    this.error,
    this.moreError,
  });

  HistoryState copyWith({
    List<SessionModel>? sessions,
    bool? loading,
    bool? loadingMore,
    bool? hasMore,
    bool? mutating,
    Object? error = _unchanged,
    Object? moreError = _unchanged,
  }) => HistoryState(
    sessions: sessions ?? this.sessions,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    hasMore: hasMore ?? this.hasMore,
    mutating: mutating ?? this.mutating,
    error: identical(error, _unchanged) ? this.error : error as String?,
    moreError: identical(moreError, _unchanged)
        ? this.moreError
        : moreError as String?,
  );
}

final historyControllerProvider =
    NotifierProvider.autoDispose<HistoryController, HistoryState>(
      HistoryController.new,
    );

class HistoryController extends Notifier<HistoryState> {
  static const pageSize = 50;

  late DatabaseService _database;
  int _generation = 0;
  bool _disposed = false;

  @override
  HistoryState build() {
    _database = ref.read(databaseServiceProvider);
    ref.onDispose(() {
      _disposed = true;
      _generation++;
    });
    return const HistoryState();
  }

  Future<void> loadFirstPage() async {
    final generation = ++_generation;
    state = state.copyWith(
      loading: state.sessions.isEmpty,
      loadingMore: false,
      error: null,
      moreError: null,
    );
    try {
      final rows = await _database.getSessions(limit: pageSize);
      if (_disposed || generation != _generation) return;
      state = state.copyWith(
        sessions: List.unmodifiable(rows),
        hasMore: rows.length == pageSize,
        loading: false,
      );
    } catch (_) {
      if (_disposed || generation != _generation) return;
      state = state.copyWith(
        loading: false,
        error: 'Could not load history. Pull down or tap Retry.',
      );
    }
  }

  Future<void> loadMore() async {
    if (_disposed ||
        state.loading ||
        state.loadingMore ||
        !state.hasMore ||
        state.mutating ||
        state.error != null) {
      return;
    }
    final generation = _generation;
    final offset = state.sessions.length;
    state = state.copyWith(loadingMore: true, moreError: null);
    try {
      final rows = await _database.getSessions(limit: pageSize, offset: offset);
      if (_disposed || generation != _generation) return;
      state = state.copyWith(
        sessions: List.unmodifiable([...state.sessions, ...rows]),
        hasMore: rows.length == pageSize,
        loadingMore: false,
      );
    } catch (_) {
      if (_disposed || generation != _generation) return;
      state = state.copyWith(
        loadingMore: false,
        moreError: 'Could not load more sessions.',
      );
    }
  }

  Future<bool> deleteSession(int id) async {
    if (_disposed || state.mutating) return false;
    state = state.copyWith(mutating: true);
    try {
      final deleted = await _database.deleteSession(id);
      if (_disposed || !deleted) return false;
      state = state.copyWith(
        sessions: List.unmodifiable(
          state.sessions.where((session) => session.id != id),
        ),
      );
      await loadFirstPage();
      return true;
    } catch (_) {
      return false;
    } finally {
      if (!_disposed) state = state.copyWith(mutating: false);
    }
  }

  Future<bool> clearAllSessions() async {
    if (_disposed || state.mutating) return false;
    state = state.copyWith(mutating: true);
    try {
      await _database.clearAllSessions();
      if (_disposed) return false;
      state = state.copyWith(sessions: const []);
      await loadFirstPage();
      return true;
    } catch (_) {
      return false;
    } finally {
      if (!_disposed) state = state.copyWith(mutating: false);
    }
  }
}
