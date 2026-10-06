import 'package:flutter/material.dart';
import 'package:fireplace/src/widgets/dialog.dart';
import 'package:fireplace/src/styles/design_tokens.dart';

Future<bool> confirmBlock(BuildContext context, String name) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => UiDialog(
      icon: Icon(
        Icons.block,
        color: FireplaceUiTokens.of(context).danger,
        size: 36,
      ),
      title: Text('Block @$name?'),
      content: Text(
        'They will not be able to start chats or send you messages, and you '
        'will not receive anything more from them. They are not told. You '
        'can unblock them any time in Settings.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('Cancel'),
        ),
        TextButton(
          key: Key('confirmBlock'),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            'Block',
            style: TextStyle(color: FireplaceUiTokens.of(context).danger),
          ),
        ),
      ],
    ),
  );
  return ok == true;
}
