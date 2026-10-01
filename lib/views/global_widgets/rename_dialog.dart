import 'package:flutter/material.dart';

class RenameDialog extends StatefulWidget {
  final String initialTitle;
  const RenameDialog({super.key, required this.initialTitle});

  static Future<String?> show(BuildContext context, String initialTitle) =>
      showDialog<String>(
        context: context,
        builder: (_) => RenameDialog(initialTitle: initialTitle),
      );

  @override
  State<RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<RenameDialog> {
  late final TextEditingController _editor;

  @override
  void initState() {
    super.initState();
    _editor = TextEditingController(text: widget.initialTitle);
  }

  @override
  void dispose() {
    _editor.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _editor.text.trim();
    if (value.isNotEmpty && value.length <= 100) Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename recording'),
    content: TextField(
      controller: _editor,
      autofocus: true,
      maxLength: 100,
      decoration: const InputDecoration(labelText: 'Name'),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      ValueListenableBuilder(
        valueListenable: _editor,
        builder: (_, value, _) => FilledButton(
          onPressed:
              value.text.trim().isNotEmpty && value.text.trim().length <= 100
              ? _submit
              : null,
          child: const Text('Save'),
        ),
      ),
    ],
  );
}
