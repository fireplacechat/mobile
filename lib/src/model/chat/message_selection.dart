import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/providers.dart';
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

  /// Removes every message still shown in this chat, on this device only.
  Future<Set<String>> deleteAllLocal() {
    final ids =
        ref
            .read(messagesProvider(chatId))
            .value
            ?.where((message) => !message.remotelyDeleted)
            .map((message) => message.id)
            .toSet() ??
        {};
    return _delete(ids);
  }

  Future<Set<String>> _delete(Set<String> ids) async {
    final owner = ref.read(appSessionProvider).value;
    if (owner == null || !available || state.deleting) return const {};
    final remaining = {...ids};
    final removed = <String>{};
    state = MessageSelection(ids: remaining, deleting: true);
    for (final id in List.of(remaining)) {
      try {
        await owner.chat.deleteMessageLocally(chatId, id);
        if (!ref.mounted ||
            !identical(ref.read(appSessionProvider).value, owner)) {
          return Set.unmodifiable(removed);
        }
        removed.add(id);
        remaining.remove(id);
        ref.read(pendingLocalSendsProvider.notifier).remove(chatId, id);
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
    state = MessageSelection();
    return Set.unmodifiable(removed);
  }
}

final messageSelectionProvider = NotifierProvider.autoDispose
    .family<MessageSelectionController, MessageSelection, String>(
      MessageSelectionController.new,
    );
