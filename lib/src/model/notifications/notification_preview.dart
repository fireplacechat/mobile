import 'package:cryptography/cryptography.dart';

import 'package:fireplace/src/crypto/codec.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/db/message_mutation.dart';
import 'package:fireplace/src/model/chat/message_limits.dart';

/// What a notification says when its message cannot be shown: previews are
/// off, the message could not be decrypted, or it did not arrive in time. The
/// same text the server's own alert shows (backend decision 0013).
const plainNotificationBody = 'New Message';

/// The title when "Show sender's name" is off.
const hiddenNotificationTitle = 'Fireplace';

/// Bodies are cut here before they are handed to the system, which shortens
/// them further on screen. Keeps the work bounded for a 16,384-character
/// message.
const maxNotificationBodyCharacters = 1000;

/// How much of the reacted-to message a reaction alert quotes.
const reactionQuoteCharacters = 40;

/// The opaque per-conversation key the server puts in each push (backend
/// `conversationKey`): the first 32 hex characters of
/// `sha256("fireplace-push:" + chatId)`. A conversation keeps one message
/// alert under this tag, so later alerts replace earlier ones.
Future<String> conversationKey(String chatId) async {
  final digest = await Sha256().hash(utf8Bytes('fireplace-push:$chatId'));
  final hex = digest.bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return hex.substring(0, 32);
}

/// The tag of a conversation's reaction alert. Separate from the message
/// alert, so a reaction never replaces the message someone has not read yet.
String reactionTag(String conversationKey) => '$conversationKey.r';

/// A change to the notifications showing for one conversation.
sealed class NotificationChange {
  const NotificationChange(this.tag);

  /// The conversation key, or its [reactionTag].
  final String tag;
}

/// Shows an alert under [tag], replacing the one there. [messageId] is kept
/// with it, so a later edit or delete finds the alert it is about.
final class ShowNotification extends NotificationChange {
  const ShowNotification({
    required String tag,
    required this.title,
    required this.body,
    required this.messageId,
    this.silent = false,
  }) : super(tag);

  final String title;
  final String body;
  final String messageId;

  /// Update what is showing without a sound or a new banner (an edit).
  final bool silent;

  @override
  bool operator ==(Object other) =>
      other is ShowNotification &&
      other.tag == tag &&
      other.title == title &&
      other.body == body &&
      other.messageId == messageId &&
      other.silent == silent;

  @override
  int get hashCode => Object.hash(tag, title, body, messageId, silent);

  @override
  String toString() =>
      'ShowNotification($tag, $title, $body, $messageId, silent: $silent)';
}

/// Removes the alert under [tag].
final class RemoveNotification extends NotificationChange {
  const RemoveNotification(super.tag);

  @override
  bool operator ==(Object other) =>
      other is RemoveNotification && other.tag == tag;

  @override
  int get hashCode => tag.hashCode;

  @override
  String toString() => 'RemoveNotification($tag)';
}

/// The title of a conversation's alerts: the sender's username, or
/// "Fireplace" when this device hides names.
String notificationTitle({required String username, required bool showName}) =>
    showName && username.isNotEmpty ? username : hiddenNotificationTitle;

/// What to change in the notifications when [arrived] has just been received
/// and saved (app decision 0030). Pure, so Android and, later, iOS share it.
///
/// - [target] is the stored message a reaction, edit or delete refers to,
///   if this device has it.
/// - [showing] maps each tag with an alert still on screen to the message id
///   it shows.
/// - With [showPreview] off every arrival from the other person gives the
///   plain alert, exactly as before previews existed.
List<NotificationChange> notificationChanges({
  required LocalMessage arrived,
  LocalMessage? target,
  required String ownUid,
  required String conversationKey,
  required String title,
  required bool showPreview,
  Map<String, String> showing = const {},
}) {
  // Our own messages, including those sent from another of our devices.
  if (arrived.senderUid == ownUid) return const [];
  final messageTag = conversationKey;
  final reactTag = reactionTag(conversationKey);
  ShowNotification plain() => ShowNotification(
    tag: messageTag,
    title: title,
    body: plainNotificationBody,
    messageId: arrived.id,
  );
  if (!showPreview || arrived.status != MessageStatus.ok) return [plain()];
  final change = arrived.mutation;
  if (change == null) {
    return [
      ShowNotification(
        tag: messageTag,
        title: title,
        body: notificationBody(arrived.body),
        messageId: arrived.id,
      ),
    ];
  }
  final usable =
      target != null &&
      target.id == change.targetId &&
      target.chatId == arrived.chatId &&
      target.mutation == null &&
      target.status == MessageStatus.ok &&
      !target.locallyDeleted;
  switch (change.kind) {
    case MessageMutationKind.reaction:
      final emoji = change.emoji;
      // Like Signal: only reactions to my own messages alert.
      final mine = usable && target.senderUid == ownUid;
      if (change.operation == ReactionOperation.set &&
          emoji.isNotEmpty &&
          mine &&
          !target.remotelyDeleted) {
        return [
          ShowNotification(
            tag: reactTag,
            title: title,
            body: reactionNotificationBody(emoji, target.body),
            messageId: change.targetId,
          ),
        ];
      }
      // A reaction taken back removes its alert if that is what shows.
      if (change.operation == ReactionOperation.clear &&
          showing[reactTag] == change.targetId) {
        return [RemoveNotification(reactTag)];
      }
      return const [];
    case MessageMutationKind.edit:
      // No new alert. An alert still showing the message gets the new text.
      if (showing[messageTag] != change.targetId) return const [];
      if (usable && target.senderUid != arrived.senderUid) return const [];
      return [
        ShowNotification(
          tag: messageTag,
          title: title,
          body: notificationBody(change.body),
          messageId: change.targetId,
          silent: true,
        ),
      ];
    case MessageMutationKind.delete:
      return [
        for (final tag in [messageTag, reactTag])
          if (showing[tag] == change.targetId) RemoveNotification(tag),
      ];
  }
}

/// A message's text as an alert body: cut to
/// [maxNotificationBodyCharacters], and "New Message" if it is empty.
String notificationBody(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return plainNotificationBody;
  if (messageCharacters(trimmed) <= maxNotificationBodyCharacters) {
    return trimmed;
  }
  return '${clipMessage(trimmed, maxNotificationBodyCharacters).trimRight()}…';
}

/// `Reacted ❤️ to “start of the message…”`.
String reactionNotificationBody(String emoji, String targetText) {
  // One line: the quote is a reminder of which message, not the message.
  final line = targetText.replaceAll(RegExp(r'\s+'), ' ').trim();
  final String quote;
  if (messageCharacters(line) <= reactionQuoteCharacters) {
    quote = line;
  } else {
    // End on a whole word where one is close, not in the middle of one.
    var clipped = clipMessage(line, reactionQuoteCharacters);
    final space = clipped.lastIndexOf(' ');
    if (space >= clipped.length ~/ 2) clipped = clipped.substring(0, space);
    quote = '${clipped.trimRight()}…';
  }
  return quote.isEmpty ? 'Reacted $emoji' : 'Reacted $emoji to “$quote”';
}
