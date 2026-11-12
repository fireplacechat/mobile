import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/db/message_mutation.dart';
import 'package:fireplace/src/model/chat/chat_service.dart';
import 'package:fireplace/src/model/notifications/chat_activity.dart';

/// Reactions this person just chose in one chat, by message id, shown at once
/// while they are sent (null: their reaction is being removed).
///
/// Signal's apps do the same: the reaction is recorded locally first, then
/// sent. When the send ends the entry goes and the saved history shows what
/// happened. A failed reaction simply is not there; nothing is said about it.
/// A send whose outcome is unknown is not repeated (the person can react
/// again), and one that reached the server but could not be saved here is
/// saved without sending it again.
class PendingReactions extends Notifier<Map<String, String?>> {
  PendingReactions(this.chatId);
  final String chatId;

  // Which tap each entry belongs to: only the latest tap's send removes it.
  final _latest = <String, int>{};
  var _taps = 0;

  @override
  Map<String, String?> build() {
    ref.watch(appSessionProvider.select((s) => s.value?.uid));
    _latest.clear();
    return const {};
  }

  Future<void> react(String messageId, String emoji) async {
    final owner = ref.read(appSessionProvider).value;
    final summary = ref.read(chatSummaryProvider(chatId));
    if (owner == null ||
        summary == null ||
        !ref.read(chatActivityProvider.notifier).eligible(summary)) {
      return;
    }
    final current = state.containsKey(messageId)
        ? state[messageId]
        : ref
              .read(messagesProvider(chatId))
              .value
              ?.where((m) => m.id == messageId)
              .firstOrNull
              ?.reactions[owner.uid]
              ?.emoji;
    final tap = ++_taps;
    _latest[messageId] = tap;
    // Choosing the reaction already there removes it, as the send does.
    state = {...state, messageId: current == emoji ? null : emoji};
    try {
      await owner.chat.react(chatId, messageId, emoji);
    } on SendNotConfirmedException catch (e) {
      if (e.outcome == SendOutcome.publishedLocalSaveFailed) {
        try {
          await owner.chat.saveControlLocally(e);
        } catch (_) {
          // The peer has it; this phone shows it after the next change.
        }
      }
    } catch (_) {
      // Not sent: the reaction is simply not there.
    }
    // Let the saved history's update arrive before the entry goes, so the
    // reaction does not blink off for a frame.
    await Future<void>.delayed(Duration.zero);
    if (!ref.mounted || _latest[messageId] != tap) return;
    _latest.remove(messageId);
    state = {...state}..remove(messageId);
  }
}

final pendingReactionsProvider = NotifierProvider.autoDispose
    .family<PendingReactions, Map<String, String?>, String>(
      PendingReactions.new,
    );

/// The chat's history with this person's pending reactions in place.
final shownMessagesProvider = Provider.autoDispose
    .family<AsyncValue<List<LocalMessage>>, String>((ref, chatId) {
      final history = ref.watch(messagesProvider(chatId));
      final pending = ref.watch(pendingReactionsProvider(chatId));
      final uid = ref.watch(appSessionProvider.select((s) => s.value?.uid));
      if (pending.isEmpty || uid == null) return history;
      return history.whenData(
        (list) => withPendingReactions(list, uid, pending),
      );
    });

/// [messages] with [uid]'s reaction replaced where [pending] has one.
List<LocalMessage> withPendingReactions(
  List<LocalMessage> messages,
  String uid,
  Map<String, String?> pending,
) => [
  for (final m in messages)
    if (!pending.containsKey(m.id))
      m
    else
      m.copyWith(
        reactions: {
          for (final e in m.reactions.entries)
            if (e.key != uid) e.key: e.value,
          if (pending[m.id] != null)
            uid: MessageReaction(
              emoji: pending[m.id],
              revision: (m.reactions[uid]?.revision ?? 0) + 1,
              deviceId: '',
              eventId: 'pending',
            ),
        },
      ),
];
