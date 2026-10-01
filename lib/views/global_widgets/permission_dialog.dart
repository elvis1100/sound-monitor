import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../theme.dart';

class MicrophonePermissionDialog extends StatelessWidget {
  final bool isPermanentlyDenied;
  final VoidCallback onRetry;

  const MicrophonePermissionDialog({
    super.key,
    required this.isPermanentlyDenied,
    required this.onRetry,
  });

  static Future<void> show(
    BuildContext context, {
    required bool isPermanentlyDenied,
    required VoidCallback onRetry,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => MicrophonePermissionDialog(
        isPermanentlyDenied: isPermanentlyDenied,
        onRetry: onRetry,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return AlertDialog(
      backgroundColor: colors.dialogSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.border),
      ),
      title: Row(
        children: [
          Icon(
            Icons.mic_off_rounded,
            color: Theme.of(context).colorScheme.error,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Microphone Required',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: Text(
        isPermanentlyDenied
            ? 'Microphone permission was permanently denied. To measure real-time sound levels, please enable microphone access in your device settings. Audio is processed strictly in memory and is never saved or transmitted.'
            : 'Sound Level Monitor needs microphone access to measure real-time ambient noise levels. Audio is processed strictly in memory and is never saved or transmitted.',
        style: TextStyle(
          color: colors.textSecondary,
          fontSize: 14,
          height: 1.4,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Dismiss', style: TextStyle(color: colors.textSecondary)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: () async {
            Navigator.of(context).pop();
            if (isPermanentlyDenied) {
              await openAppSettings();
            } else {
              onRetry();
            }
          },
          child: Text(
            isPermanentlyDenied ? 'Open Settings' : 'Allow Access',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
