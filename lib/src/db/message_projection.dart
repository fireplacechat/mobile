import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/db/message_mutation.dart';

/// Linear passes; target lookup never scans history for each event.
/// Kept inside the durable write, so remote deletion also erases the stored body.
Map<String, LocalMessage> projectMessageRecords(
  Map<String, LocalMessage> records,
) {
  final next = {...records};
  final deleted = <String>{};
  final reactions = <String, Map<String, MessageReaction>>{};
  final clocks = <String, Map<String, int>>{};
  for (final event in records.values) {
    final change = event.mutation;
    if (change == null) continue;
    final target = records[change.targetId];
    if (target == null ||
        target.mutation != null ||
        target.chatId != event.chatId) {
      continue;
    }
    if (target.locallyDeleted) {
      next[event.id] = LocalMessage.tombstone(event.chatId, event.id);
      continue;
    }
    if (change.kind == MessageMutationKind.reaction) {
      final byActor = clocks.putIfAbsent(
        target.id,
        () => {...target.reactionClocks},
      );
      if (change.revision > (byActor[event.senderUid] ?? 0)) {
        byActor[event.senderUid] = change.revision;
      }
    }
    if (event.status != MessageStatus.ok) continue;
    if (change.kind == MessageMutationKind.delete) {
      if (target.senderUid == event.senderUid) deleted.add(target.id);
      continue;
    }
    if (target.status != MessageStatus.ok || target.remotelyDeleted) continue;
    final actor = MessageReaction(
      emoji: change.operation == ReactionOperation.set ? change.emoji : null,
      revision: change.revision,
      deviceId: event.senderDevice,
      eventId: event.id,
    );
    final byActor = reactions.putIfAbsent(
      target.id,
      () => {...target.reactions},
    );
    final previous = byActor[event.senderUid];
    if (previous == null || actor.newerThan(previous)) {
      byActor[event.senderUid] = actor;
    }
  }
  for (final target in records.values) {
    if (!target.visible) continue;
    if (target.remotelyDeleted || deleted.contains(target.id)) {
      next[target.id] = target.copyWith(
        body: '',
        remotelyDeleted: true,
        reactions: const {},
        reactionClocks: const {},
      );
    } else if (reactions.containsKey(target.id) ||
        clocks.containsKey(target.id)) {
      next[target.id] = target.copyWith(
        reactions: reactions[target.id],
        reactionClocks: clocks[target.id],
      );
    }
  }
  // A deleted target must not leave reaction content in hidden control records.
  for (final event in records.values) {
    final change = event.mutation;
    if (change?.kind == MessageMutationKind.reaction &&
        next[change!.targetId]?.remotelyDeleted == true) {
      next[event.id] = LocalMessage.tombstone(event.chatId, event.id);
    }
  }
  for (final message in next.values.toList()) {
    final quote = message.quote;
    if (quote == null) continue;
    final original = next[quote.targetId];
    if (message.remotelyDeleted ||
        original?.locallyDeleted == true ||
        original?.remotelyDeleted == true) {
      next[message.id] = message.copyWith(quote: quote.withoutContent());
    }
  }
  return next;
}
