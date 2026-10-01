import 'package:flutter/material.dart';

import '../../../controllers/monitor_controller.dart';
import 'live_graph_widget.dart';

class MonitorControlBar extends StatelessWidget {
  final MonitorState state;
  final GraphMode graphMode;
  final VoidCallback onGraphMode;
  final VoidCallback onSave;
  final VoidCallback onPlayPause;
  final VoidCallback onReset;
  final VoidCallback onCalibrate;

  const MonitorControlBar({
    super.key,
    required this.state,
    required this.graphMode,
    required this.onGraphMode,
    required this.onSave,
    required this.onPlayPause,
    required this.onReset,
    required this.onCalibrate,
  });

  @override
  Widget build(BuildContext context) {
    final seconds = state.elapsedSeconds % 60;
    final minutes = state.elapsedSeconds ~/ 60;
    final time =
        '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    final scheme = Theme.of(context).colorScheme;
    final enabled = !state.isBusy && !state.pendingSave;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.circle,
                    size: 8,
                    color: state.isRecording ? scheme.error : scheme.outline,
                  ),
                  const SizedBox(width: 8),
                  if (state.isRecording) ...[
                    Text(
                      'REC',
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: scheme.error),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(time, style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton.filledTonal(
                    tooltip: 'Graph: ${graphMode.label}. Show next graph',
                    icon: Icon(graphMode.icon),
                    onPressed: onGraphMode,
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Save session and pause',
                    icon: const Icon(Icons.save_alt),
                    onPressed: enabled && state.hasSession ? onSave : null,
                  ),
                  IconButton.filled(
                    tooltip: state.isRecording
                        ? 'Pause monitoring'
                        : 'Play monitoring',
                    iconSize: 32,
                    style: IconButton.styleFrom(
                      minimumSize: const Size(62, 62),
                    ),
                    icon: Icon(
                      state.isRecording ? Icons.pause : Icons.play_arrow,
                    ),
                    onPressed: enabled ? onPlayPause : null,
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Reset unsaved measurement',
                    icon: const Icon(Icons.restart_alt),
                    onPressed: enabled && state.hasSession ? onReset : null,
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Calibrate microphone',
                    icon: const Icon(Icons.tune),
                    onPressed: onCalibrate,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
