import 'package:flutter/material.dart';
import 'package:fireplace/src/widgets/dialog.dart';

Future<bool?> confirmAnotherMessageCopy(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => UiDialog(
      title: const Text('Send another copy?'),
      content: const SingleChildScrollView(
        child: Text(
          'The original may already have been delivered. This sends a new message.',
        ),
      ),
      actions: [
        TextButton(
          key: const Key('cancelResend'),
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('confirmResend'),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Send another copy'),
        ),
      ],
    ),
  );
}
