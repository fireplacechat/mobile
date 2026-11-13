import 'package:flutter/material.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/fireplace_crypto.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/widgets/dialog.dart';

Future<void> reviewChatIdentity(
  BuildContext context,
  AppSession session,
  String peerUid,
  List<int> newIdentityPub, {
  required bool Function() isMounted,
  required void Function(String) notice,
}) async {
  final newFp = await identityFingerprint(newIdentityPub);
  final oldPin = await session.keys.pinnedIdentity(peerUid);
  final oldFp = oldPin == null ? null : await identityFingerprint(oldPin);
  if (!isMounted() || !context.mounted) return;
  final trust = await showDialog<bool>(
    context: context,
    builder: (ctx) => UiDialog(
      icon: Icon(
        Icons.warning_amber_rounded,
        color: FireplaceUiTokens.of(context).danger,
        size: 40,
      ),
      title: Text('Security code changed'),
      content: SingleChildScrollView(
        child: Text(
          "This contact's identity key is different from the one you saw "
          'before. That can happen if they reinstalled the app or lost '
          'their phone, but it can also mean someone is interfering. '
          'Messages to and from them are on hold.\n\n'
          '${oldFp == null ? '' : 'Previous key:\n$oldFp\n\n'}'
          'New key:\n$newFp\n\n'
          'Ask them (in person or over a call you trust) to read you the '
          'fingerprint under Settings, and only trust the new key if it '
          'matches.',
        ),
      ),
      actions: [
        TextButton(
          key: Key('keepBlocked'),
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('Keep on hold'),
        ),
        TextButton(
          key: Key('trustNew'),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            'Trust new key',
            style: TextStyle(color: FireplaceUiTokens.of(context).danger),
          ),
        ),
      ],
    ),
  );
  if (trust == true) {
    await session.keys.acceptIdentityChange(peerUid, newIdentityPub);
    await session.chat.retryDeferred(); // delivers what was held back
    notice('New key trusted.');
  }
}
