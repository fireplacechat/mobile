import 'package:flutter/material.dart';

import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/view/safety/confirm_block.dart';
import 'package:fireplace/src/view/safety/report_spam.dart';

// What the chat screen does when the person blocks or reports the other
// person. Each leaves the chat once the change is stored.

/// Asks first, then blocks.
Future<void> blockAfterConfirming(
  BuildContext context,
  AppSession session,
  String peerUid,
  String name,
) async {
  if (!await confirmBlock(context, name) || !context.mounted) return;
  await session.safety.block(peerUid);
  if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
}

/// Blocks without asking: the profile screen already confirmed.
Future<void> blockConfirmed(
  BuildContext context,
  AppSession session,
  String peerUid,
) async {
  await session.safety.block(peerUid);
  if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
}

/// Reports spam, and blocks too when [choice] says so. [notice] tells the
/// person what happened.
Future<void> reportSpam(
  BuildContext context,
  AppSession session,
  String peerUid,
  ReportSpamChoice choice, {
  required void Function(String message) notice,
}) async {
  await session.safety.reportSpam(peerUid);
  if (!context.mounted) return;
  if (choice == ReportSpamChoice.reportAndBlock) {
    await session.safety.block(peerUid);
    if (!context.mounted) return;
    notice('Reported as spam and blocked.');
    Navigator.of(context).popUntil((r) => r.isFirst);
    return;
  }
  notice('Reported as spam.');
}
