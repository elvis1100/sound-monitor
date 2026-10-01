import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/session_model.dart';
import '../../../theme.dart';

class SessionCard extends StatelessWidget {
  final SessionModel session;
  final bool enabled;
  final VoidCallback onDelete;
  final VoidCallback onOpen;

  const SessionCard({
    super.key,
    required this.session,
    required this.enabled,
    required this.onDelete,
    required this.onOpen,
  });

  String get _measurementLabel => switch (session.measurementType) {
    MeasurementType.legacyEstimate => 'Legacy estimate',
    MeasurementType.estimatedDbA => 'Estimated dB(A)',
    MeasurementType.referenceAdjustedDbA => 'Reference-adjusted dB(A)',
    MeasurementType.estimatedDbC => 'Estimated dB(C)',
    MeasurementType.referenceAdjustedDbC => 'Reference-adjusted dB(C)',
    MeasurementType.estimatedDbZ => 'Estimated dB(Z)',
    MeasurementType.referenceAdjustedDbZ => 'Reference-adjusted dB(Z)',
    MeasurementType.manualAdjustedDbA => 'Manual offset dB(A)',
    MeasurementType.manualAdjustedDbC => 'Manual offset dB(C)',
    MeasurementType.manualAdjustedDbZ => 'Manual offset dB(Z)',
  };

  String _formatDuration(int durationSeconds) {
    final minutes = durationSeconds ~/ 60;
    final seconds = durationSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onOpen : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      session.title,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Text(_formatDuration(session.durationSeconds)),
                  IconButton(
                    tooltip: 'Delete session',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: enabled ? onDelete : null,
                  ),
                ],
              ),
              Text(
                DateFormat('dd MMM yyyy, h:mm a').format(session.date),
                style: TextStyle(color: colors.textSecondary),
              ),
              Text(
                session.measurementType == MeasurementType.legacyEstimate
                    ? _measurementLabel
                    : '$_measurementLabel · ${session.timeResponse.label}',
                style: TextStyle(color: colors.textSecondary),
              ),
              if (session.statsDurationSeconds < session.durationSeconds)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'MIN/AVG/MAX: last ${_formatDuration(session.statsDurationSeconds)} at these settings',
                    style: TextStyle(color: colors.textSecondary),
                  ),
                ),
              if (session.audioFilePath != null) ...[
                const SizedBox(height: 8),
                const Row(
                  children: [
                    Icon(Icons.play_circle_outline, size: 18),
                    SizedBox(width: 6),
                    Text('Audio recording'),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _stat('MIN', session.minDb),
                  _stat('AVG', session.avgDb),
                  _stat('MAX', session.maxDb),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(String label, double value) => Column(
    children: [
      Text(label),
      Text(session.hasLevelSamples ? value.toStringAsFixed(1) : '—'),
    ],
  );
}
