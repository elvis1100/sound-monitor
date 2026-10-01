import 'package:flutter/material.dart';

import '../../../controllers/recording_controller.dart';
import '../../../theme.dart';
import '../recording_format.dart';
import 'recording_timeline_chart.dart';

class RecordingPlayer extends StatelessWidget {
  final RecordingState state;
  final VoidCallback onPlayPause;
  final ValueChanged<int> onSeek;

  const RecordingPlayer({
    super.key,
    required this.state,
    required this.onPlayPause,
    required this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    final session = state.session!;
    final theme = Theme.of(context);
    final duration = state.durationMilliseconds;
    final position = state.playback.positionMilliseconds.clamp(0, duration);
    final enabled = state.ready && !state.busy && duration > 0;
    final point = state.point;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _transport(context, enabled, position),
        const SizedBox(height: AppTheme.recordingSectionSpacing),
        const Divider(height: 1),
        const SizedBox(height: 12),
        Text('Level timeline', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text('dB', style: theme.textTheme.bodySmall),
        if (session.recordingTimeline.isNotEmpty)
          RecordingTimelineChart(
            points: session.recordingTimeline,
            durationMilliseconds: duration,
            positionMilliseconds: position,
            onSeek: enabled ? onSeek : null,
          )
        else
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('No saved level timeline'),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('00:00', style: theme.textTheme.bodySmall),
            Text(recordingTime(duration), style: theme.textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${point?.db?.toStringAsFixed(1) ?? '—'} '
            '${(point?.weighting ?? session.frequencyWeighting).unit} '
            'at ${recordingTime(position)}',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(recordingTime(position), style: theme.textTheme.bodySmall),
            Expanded(
              child: Slider(
                value: position.toDouble(),
                min: 0,
                max: duration > 0 ? duration.toDouble() : 1,
                semanticFormatterCallback: (value) =>
                    recordingTime(value.round()),
                onChanged: enabled ? (value) => onSeek(value.round()) : null,
              ),
            ),
            Text(recordingTime(duration), style: theme.textTheme.bodySmall),
          ],
        ),
      ],
    );
  }

  Widget _transport(BuildContext context, bool enabled, int position) {
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(
        Size(0, AppTheme.recordingControlHeight),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 12),
      ),
    );
    final play = Tooltip(
      message: state.playback.playing
          ? 'Pause recording playback'
          : 'Play recording',
      child: FilledButton.icon(
        style: style,
        onPressed: enabled ? onPlayPause : null,
        icon: Icon(state.playback.playing ? Icons.pause : Icons.play_arrow),
        label: Text(state.playback.playing ? 'Pause' : 'Play'),
      ),
    );
    final outlinedStyle = style.copyWith(
      side: WidgetStatePropertyAll(
        BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.recordingControlRadius),
        ),
      ),
    );
    Widget skip(String label, String tooltip, int offset) => Tooltip(
      message: tooltip,
      child: OutlinedButton(
        style: outlinedStyle,
        onPressed: enabled ? () => onSeek(position + offset) : null,
        child: Text(label),
      ),
    );
    final back = skip('−5 s', 'Back 5 seconds', -5000);
    final forward = skip('+5 s', 'Forward 5 seconds', 5000);
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow =
            constraints.maxWidth <
            MediaQuery.textScalerOf(
              context,
            ).scale(AppTheme.recordingToolbarRowWidth);
        final skips = Row(
          children: [
            Expanded(child: back),
            const SizedBox(width: 8),
            Expanded(child: forward),
          ],
        );
        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [play, const SizedBox(height: 8), skips],
          );
        }
        return Row(
          children: [
            Expanded(flex: 4, child: play),
            const SizedBox(width: 8),
            Expanded(flex: 5, child: skips),
          ],
        );
      },
    );
  }
}
