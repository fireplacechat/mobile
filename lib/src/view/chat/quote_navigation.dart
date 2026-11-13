import 'package:flutter/material.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/view/chat/timeline_scroll.dart';

Future<void> locateQuotedMessage(
  BuildContext context,
  TimelineScroll timeline,
  List<LocalMessage> messages,
  String id, {
  required ValueChanged<String> notice,
  ValueChanged<String>? onFound,
}) async {
  if (!messages.any(
    (m) => m.id == id && !m.remotelyDeleted && m.status == MessageStatus.ok,
  )) {
    notice('The original message is no longer available on this device.');
    return;
  }
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  final found = await timeline.locate(
    id,
    messages.map((m) => m.id).toList(),
    reduceMotion: reduceMotion,
  );
  if (found) onFound?.call(id);
  if (context.mounted && !found) {
    notice(
      'Could not locate the original message. Try searching this conversation.',
    );
  }
}
