import 'package:flutter/material.dart';
import 'package:fireplace/src/widgets/dialog.dart';

/// Asks for one line of text and pops with it (or null on Cancel). The dialog
/// owns its controller: disposing it in the caller while the dialog was still
/// animating closed crashed the app on the device.
class TextPromptDialog extends StatefulWidget {
  const TextPromptDialog({
    super.key,
    required this.title,
    required this.initial,
    this.maxLength,
    this.fieldKey,
    this.saveKey,
  });
  final String title, initial;
  final int? maxLength;
  final Key? fieldKey, saveKey;

  @override
  State<TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<TextPromptDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UiDialog(
    title: Text(widget.title),
    content: TextField(
      key: widget.fieldKey,
      controller: _controller,
      autofocus: true,
      maxLines: null,
      maxLength: widget.maxLength,
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        key: widget.saveKey,
        onPressed: () => Navigator.pop(context, _controller.text),
        child: const Text('Save'),
      ),
    ],
  );
}
