import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/session_model.dart';
import '../../controllers/history_controller.dart';
import '../../theme.dart';
import '../global_widgets/confirm_delete_dialog.dart';
import '../recording/recording_view.dart';
import 'widgets/session_card.dart';

class HistoryView extends ConsumerStatefulWidget {
  const HistoryView({super.key});

  @override
  ConsumerState<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends ConsumerState<HistoryView> {
  late final HistoryController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(historyControllerProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_controller.loadFirstPage());
    });
  }

  Future<void> _deleteSession(SessionModel session) async {
    final confirmed = await ConfirmDeleteDialog.show(
      context,
      title: 'Delete Session',
      content: 'Delete this saved session?',
    );
    if (!mounted || confirmed != true || session.id == null) return;
    final deleted = await _controller.deleteSession(session.id!);
    if (mounted) {
      _showFeedback(
        deleted ? 'Session deleted.' : 'Could not delete session. Try again.',
      );
    }
  }

  Future<void> _clearAllSessions() async {
    final confirmed = await ConfirmDeleteDialog.show(
      context,
      title: 'Clear All History',
      content: 'Permanently delete all saved sound sessions?',
      confirmLabel: 'Clear All',
    );
    if (!mounted || confirmed != true) return;
    final cleared = await _controller.clearAllSessions();
    if (mounted) {
      _showFeedback(
        cleared
            ? 'All sessions cleared.'
            : 'Could not clear history. Try again.',
      );
    }
  }

  Future<void> _openSession(SessionModel session) async {
    if (session.id == null) return;
    final deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => RecordingView(sessionId: session.id!)),
    );
    if (!mounted) return;
    if (deleted == true) _showFeedback('Recording deleted.');
    await _controller.loadFirstPage();
  }

  void _showFeedback(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final history = ref.watch(historyControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          if (history.sessions.isNotEmpty)
            IconButton(
              tooltip: 'Clear all history',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: history.mutating ? null : _clearAllSessions,
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _controller.loadFirstPage,
        child: _buildBody(history, colors),
      ),
    );
  }

  Widget _buildBody(HistoryState history, AppColors colors) {
    if (history.loading && history.sessions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (history.sessions.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          Center(
            child: Text(
              history.error ?? 'No saved sessions yet.',
              style: TextStyle(color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ),
          if (history.error != null)
            Center(
              child: TextButton(
                onPressed: _controller.loadFirstPage,
                child: const Text('Retry'),
              ),
            ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount:
          history.sessions.length +
          (history.hasMore || history.error != null || history.moreError != null
              ? 1
              : 0),
      itemBuilder: (context, index) {
        if (index < history.sessions.length) {
          final session = history.sessions[index];
          return SessionCard(
            session: session,
            enabled: !history.mutating,
            onDelete: () => _deleteSession(session),
            onOpen: () => _openSession(session),
          );
        }
        return Center(
          child: Column(
            children: [
              if (history.error != null) ...[
                Text(history.error!, textAlign: TextAlign.center),
                TextButton(
                  onPressed: _controller.loadFirstPage,
                  child: const Text('Retry'),
                ),
              ],
              if (history.moreError != null)
                Text(history.moreError!, textAlign: TextAlign.center),
              if (history.loadingMore)
                const CircularProgressIndicator()
              else if (history.hasMore && history.error == null)
                TextButton(
                  onPressed: _controller.loadMore,
                  child: const Text('Load more'),
                ),
            ],
          ),
        );
      },
    );
  }
}
