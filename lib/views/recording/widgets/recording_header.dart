import 'package:flutter/material.dart';

class RecordingHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onRename;

  const RecordingHeader({super.key, required this.title, this.onRename});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      const SizedBox(width: 8),
      IconButton(
        tooltip: 'Rename recording',
        icon: const Icon(Icons.edit_outlined),
        onPressed: onRename,
      ),
    ],
  );
}
