import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/session_model.dart';
import '../../../theme.dart';
import '../recording_format.dart';

class RecordingSummary extends StatelessWidget {
  final SessionModel session;
  const RecordingSummary({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final details = [
      (
        'Duration',
        recordingTime(
          session.audioDurationMilliseconds ?? session.durationSeconds * 1000,
        ),
      ),
      ('Weighting', session.frequencyWeighting.unit),
      ('Response', session.timeResponse.label),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Session summary', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _stat(context, 'Minimum', session.minDb),
            const SizedBox(width: 12),
            _stat(context, 'Average', session.avgDb),
            const SizedBox(width: 12),
            _stat(context, 'Peak', session.maxDb),
          ],
        ),
        if (session.statsDurationSeconds < session.durationSeconds) ...[
          const SizedBox(height: 12),
          Text(
            'Statistics: last ${recordingTime(session.statsDurationSeconds * 1000)} at these settings',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 12),
        const Divider(height: 1),
        const SizedBox(height: 8),
        _detail(
          context,
          'Recorded',
          DateFormat('dd MMM yyyy, h:mm a').format(session.date.toLocal()),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final narrow =
                constraints.maxWidth <
                MediaQuery.textScalerOf(
                  context,
                ).scale(AppTheme.recordingDetailsRowWidth);
            if (narrow) {
              return Column(
                children: [
                  for (final (label, value) in details)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              label,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(value),
                        ],
                      ),
                    ),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < details.length; index++) ...[
                  if (index != 0) const SizedBox(width: 12),
                  Expanded(
                    child: _detail(
                      context,
                      details[index].$1,
                      details[index].$2,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _stat(BuildContext context, String label, double value) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            session.hasLevelSamples ? '${value.toStringAsFixed(1)} dB' : '—',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontSize: AppTheme.recordingStatFontSize,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _detail(BuildContext context, String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 4),
      Text(value),
    ],
  );
}
