import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/model/chat/message_controls.dart';
import 'package:fireplace/src/model/chat/pending_sends.dart';
import 'package:fireplace/src/model/notifications/chat_activity.dart';

class MessageSelection {
  MessageSelection({
    Set<String> ids = const {},
    this.deleting = false,
    this.error,
  }) : ids = Set.unmodifiable(ids);
  final Set<String> ids;
  final bool deleting;
  final String? error;
  bool get active => ids.isNotEmpty || deleting;
}

class MessageSelectionController extends Notifier<MessageSelection> {
  MessageSelectionController(this.chatId);
  final String chatId;

  @override
  MessageSelection build() {
    ref.watch(appSessionProvider.select((s) => s.value?.uid));
    ref.watch(blockedUidsProvider);
    ref.watch(hiddenChatsProvider);
    ref.watch(identityAlertsProvider);
    return MessageSelection();
  }

  bool get available {
    final summary = ref.read(chatSummaryProvider(chatId));
    return summary != null &&
        ref.read(chatActivityProvider.notifier).eligible(summary);
  }

  void toggle(String id) {
    if (state.deleting || !available) return;
    final next = {...state.ids};
    if (!next.remove(id)) next.add(id);
    state = MessageSelection(ids: next);
  }

  void clear() {
    if (!state.deleting) state = MessageSelection();
  }

  Future<Set<String>> deleteSelected() => _delete({...state.ids});

  /// Removes every message still shown in this chat.
  ///
  /// A message you sent, whose send is confirmed, is deleted for everyone.
  /// Anything else is removed on this device only. The other person's own
  /// messages are never sent as a delete.
  Future<Set<String>> deleteAll() async {
    final owner = ref.read(appSessionProvider).value;
    if (owner == null || !available || state.deleting) return const {};
    final shown =
        ref
            .read(messagesProvider(chatId))
            .value
            ?.where((message) => !message.remotelyDeleted)
            .toList(growable: false) ??
        const <LocalMessage>[];
    final local = <String>[];
    final remote = <String>[];
    for (final message in shown) {
      if (message.outgoing && message.status == MessageStatus.ok) {
        remote.add(message.id);
      } else {
        local.add(message.id);
      }
    }
    final removed = await _delete({...local, ...remote}, stopAfter: local);
    if (!ref.mounted ||
        !identical(ref.read(appSessionProvider).value, owner) ||
        state.error != null) {
      return removed;
    }
    for (final id in remote) {
      final sent = await ref
          .read(messageControlsProvider(chatId).notifier)
          .delete(id);
      if (!ref.mounted ||
          !identical(ref.read(appSessionProvider).value, owner)) {
        return removed;
      }
      if (!sent) {
        // The control notice explains the failure. Do not keep deleting,
        // and do not treat the rest as removed on the other device.
        state = MessageSelection();
        return Set.unmodifiable(removed);
      }
      removed.add(id);
      ref.read(pendingLocalSendsProvider.notifier).remove(chatId, id);
      final left = {...state.ids}..remove(id);
      state = MessageSelection(ids: left, deleting: true);
    }
    state = MessageSelection();
    return Set.unmodifiable(removed);
  }

  /// Deletes [ids] on this device. When [stopAfter] is set, selection stays
  /// open so a following remote delete can finish the same action.
  Future<Set<String>> _delete(
    Set<String> ids, {
    List<String>? stopAfter,
  }) async {
    final owner = ref.read(appSessionProvider).value;
    if (owner == null || !available || state.deleting) return const {};
    final remaining = {...ids};
    final removed = <String>{};
    final localIds = stopAfter ?? ids.toList();
    state = MessageSelection(ids: remaining, deleting: true);
    for (final id in localIds) {
      if (!remaining.contains(id)) continue;
      try {
        await owner.chat.deleteMessageLocally(chatId, id);
        if (!ref.mounted ||
            !identical(ref.read(appSessionProvider).value, owner)) {
          return Set.unmodifiable(removed);
        }
        removed.add(id);
        remaining.remove(id);
        ref.read(pendingLocalSendsProvider.notifier).remove(chatId, id);
        state = MessageSelection(ids: remaining, deleting: true);
      } catch (_) {
        if (!ref.mounted ||
            !identical(ref.read(appSessionProvider).value, owner)) {
          return Set.unmodifiable(removed);
        }
        state = MessageSelection(
          ids: remaining,
          error: 'Could not delete some messages on this device. Try again.',
        );
        return Set.unmodifiable(removed);
      }
    }
    if (stopAfter == null) state = MessageSelection();
    return stopAfter == null ? Set.unmodifiable(removed) : removed;
  }
}

final messageSelectionProvider = NotifierProvider.autoDispose
    .family<MessageSelectionController, MessageSelection, String>(
      MessageSelectionController.new,
    );
