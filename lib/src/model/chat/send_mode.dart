import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:fireplace/src/model/chat/chat_exceptions.dart';
import 'package:fireplace/src/model/chat/chat_tuning.dart';

/// How a send changes the chat it goes into (decision 0004: message requests).
enum SendMode {
  /// The chat is accepted, or was created before message requests existed.
  normal,

  /// I started the chat and they have not accepted yet: at most
  /// [ChatTuning.requestLimit] messages, counted on the chat document.
  request,

  /// They started the chat; my reply accepts it.
  accepting;

  /// The mode for a send into [chat] (the chat document's fields) by [uid].
  /// Throws a [ChatException] when the send is not allowed: a reaction, edit,
  /// delete or quote before the chat is accepted, or a request over its limit.
  static SendMode check(
    Map<String, dynamic> chat, {
    required String uid,
    required bool changesMessage,
  }) {
    final accepted = (chat['accepted'] as bool?) ?? true;
    if (changesMessage && !accepted) {
      throw ChatException(
        'Accept this conversation before reacting or deleting for everyone.',
      );
    }
    final mode = accepted
        ? normal
        : chat['initiator'] == uid
        ? request
        : accepting;
    if (mode == request &&
        ((chat['requestCount'] as int?) ?? 0) >= ChatTuning.requestLimit) {
      throw ChatException(
        'Waiting for them to accept your message request before you can '
        'send more.',
      );
    }
    return mode;
  }

  /// The change to the chat document that goes in the same batch as the
  /// message, or null when there is none.
  Map<String, Object>? get chatChange => switch (this) {
    normal => null,
    request => {
      'lastMessageAt': FieldValue.serverTimestamp(),
      'requestCount': FieldValue.increment(1),
    },
    accepting => {
      'lastMessageAt': FieldValue.serverTimestamp(),
      'accepted': true,
    },
  };
}
