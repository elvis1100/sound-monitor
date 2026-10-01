import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controllers/recording_controller.dart';
import '../../theme.dart';
import '../global_widgets/confirm_delete_dialog.dart';
import '../global_widgets/rename_dialog.dart';
import 'widgets/recording_actions.dart';
import 'widgets/recording_header.dart';
import 'widgets/recording_player.dart';
import 'widgets/recording_summary.dart';

class RecordingView extends ConsumerStatefulWidget {
  final int sessionId;
  const RecordingView({super.key, required this.sessionId});
  @override
  ConsumerState<RecordingView> createState() => _RecordingViewState();
}

class _RecordingViewState extends ConsumerState<RecordingView>
    with WidgetsBindingObserver {
  late final RecordingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(
      recordingControllerProvider(widget.sessionId).notifier,
    );
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_controller.load());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(_controller.pause());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _rename() async {
    final session = ref
        .read(recordingControllerProvider(widget.sessionId))
        .session;
    if (session == null) return;
    final title = await RenameDialog.show(context, session.title);
    if (!mounted || title == null) return;
    if (await _controller.rename(title) && mounted) {
      _feedback('Recording renamed.');
    }
  }

  Future<void> _delete() async {
    final confirmed = await ConfirmDeleteDialog.show(
      context,
      title: 'Delete recording',
      content: 'Delete this session and its saved audio?',
    );
    if (!mounted || confirmed != true) return;
    if (await _controller.delete() && mounted) Navigator.pop(context, true);
  }

  Future<void> _export() async {
    final saved = await _controller.exportAudio();
    if (mounted && saved == true) _feedback('WAV exported.');
  }

  void _feedback(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(recordingControllerProvider(widget.sessionId));
    final scheme = Theme.of(context).colorScheme;
    final actionsEnabled = !state.busy && !state.loading;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: const Text('Saved audio'),
        centerTitle: false,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        child: state.loading && state.session == null
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.recordingPagePadding,
                  8,
                  AppTheme.recordingPagePadding,
                  AppTheme.recordingPagePadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (state.session != null) ...[
                      RecordingHeader(
                        title: state.session!.title,
                        onRename: actionsEnabled
                            ? () => unawaited(_rename())
                            : null,
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (state.loading || state.busy)
                      const LinearProgressIndicator(),
                    if (state.error != null)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              Text(state.error!, textAlign: TextAlign.center),
                              TextButton(
                                onPressed: actionsEnabled
                                    ? _controller.load
                                    : null,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (state.session != null) ...[
                      RecordingPlayer(
                        state: state,
                        onPlayPause: () =>
                            unawaited(_controller.togglePlayback()),
                        onSeek: (milliseconds) =>
                            unawaited(_controller.seek(milliseconds)),
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      RecordingSummary(session: state.session!),
                      const SizedBox(height: AppTheme.recordingSectionSpacing),
                      RecordingActions(
                        audioEnabled: state.ready && actionsEnabled,
                        deleteEnabled: actionsEnabled,
                        onExport: () => unawaited(_export()),
                        onShare: () => unawaited(_controller.shareAudio()),
                        onDelete: () => unawaited(_delete()),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}
