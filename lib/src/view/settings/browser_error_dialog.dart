import 'package:fireplace/src/widgets/dialog.dart';
import 'package:flutter/material.dart';

Future<void> showBrowserErrorDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (dialogContext) => UiDialog(
    title: const Text('Could not open link'),
    content: const Text('Could not open your browser. Try again.'),
    actions: [
      TextButton(
        key: const Key('dismissBrowserError'),
        onPressed: () => Navigator.of(dialogContext).pop(),
        child: const Text('OK'),
      ),
    ],
  ),
);
