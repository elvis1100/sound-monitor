import 'package:flutter/material.dart';

import '../../../theme.dart';

class RecordingActions extends StatelessWidget {
  final bool audioEnabled;
  final bool deleteEnabled;
  final VoidCallback onExport;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  const RecordingActions({
    super.key,
    required this.audioEnabled,
    required this.deleteEnabled,
    required this.onExport,
    required this.onShare,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      LayoutBuilder(
        builder: (context, constraints) {
          final style = OutlinedButton.styleFrom(
            minimumSize: const Size(0, AppTheme.recordingControlHeight),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                AppTheme.recordingControlRadius,
              ),
            ),
          );
          final export = OutlinedButton.icon(
            style: style,
            onPressed: audioEnabled ? onExport : null,
            icon: const Icon(Icons.file_download_outlined, size: 20),
            label: const Text('Export WAV'),
          );
          final share = OutlinedButton.icon(
            style: style,
            onPressed: audioEnabled ? onShare : null,
            icon: const Icon(Icons.share_outlined, size: 20),
            label: const Text('Share'),
          );
          if (constraints.maxWidth <
              MediaQuery.textScalerOf(
                context,
              ).scale(AppTheme.recordingDetailsRowWidth)) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [export, const SizedBox(height: 12), share],
            );
          }
          return Row(
            children: [
              Expanded(child: export),
              const SizedBox(width: 12),
              Expanded(child: share),
            ],
          );
        },
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: deleteEnabled ? onDelete : null,
        style: TextButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.error,
          minimumSize: const Size(0, AppTheme.recordingControlHeight),
        ),
        child: const Text('Delete recording'),
      ),
    ],
  );
}
