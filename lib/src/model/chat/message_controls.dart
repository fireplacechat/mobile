import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/chat/chat_service.dart';
import 'package:fireplace/src/model/notifications/chat_activity.dart';

final messageControlNowProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

class MessageControlState {
  const MessageControlState({this.busy = false, this.notice, this.pending});
  final bool busy;
  final String? notice;
  final SendNotConfirmedException? pending;
}

class MessageControls extends Notifier<MessageControlState> {
  MessageControls(this.chatId);
  final String chatId;
  @override
  MessageControlState build() {
    ref.watch(appSessionProvider.select((s) => s.value?.uid));
    return const MessageControlState();
  }

  Future<bool> edit(String id, String body) =>
      _run((chat) => chat.editMessage(chatId, id, body));

  Future<bool> delete(String id) =>
      _run((chat) => chat.deleteForEveryone(chatId, id));

  Future<bool> _run(Future<void> Function(ChatService) action) async {
    final owner = ref.read(appSessionProvider).value;
    final summary = ref.read(chatSummaryProvider(chatId));
    if (state.busy ||
        owner == null ||
        summary == null ||
        !ref.read(chatActivityProvider.notifier).eligible(summary)) {
      return false;
    }
    state = const MessageControlState(busy: true);
    try {
      await action(owner.chat);
      if (!ref.mounted ||
          !identical(ref.read(appSessionProvider).value, owner)) {
        return false;
      }
      state = const MessageControlState();
      return true;
    } on SendNotConfirmedException catch (e) {
      if (!ref.mounted ||
          !identical(ref.read(appSessionProvider).value, owner)) {
        return false;
      }
      state = MessageControlState(
        pending: e,
        notice: e.outcome == SendOutcome.publishedLocalSaveFailed
            ? 'Sent, but could not save the change on this device.'
            : 'Could not confirm the change. It may have reached them. Nothing was sent again.',
      );
      return true; // The attempt moved to explicit recovery; never leave a resend-ready edit.
    } on ChatException catch (e) {
      if (!ref.mounted ||
          !identical(ref.read(appSessionProvider).value, owner)) {
        return false;
      }
      state = MessageControlState(notice: e.message);
    } catch (_) {
      if (!ref.mounted ||
          !identical(ref.read(appSessionProvider).value, owner)) {
        return false;
      }
      state = const MessageControlState(
        notice: 'Could not make this change. Try again.',
      );
    }
    return false;
  }

  Future<void> resolvePending() async {
    final owner = ref.read(appSessionProvider).value;
    final pending = state.pending;
    if (pending == null) return;
    await _run((chat) async {
      if (pending.outcome == SendOutcome.publishedLocalSaveFailed) {
        await chat.saveControlLocally(pending);
      } else {
        final outcome = await chat.checkSendStatus(chatId, pending.messageId);
        if (!ref.mounted ||
            !identical(ref.read(appSessionProvider).value, owner)) {
          return;
        }
        if (outcome != SendOutcome.confirmed) throw pending;
        // If even the warning failed to save, server evidence permits repair.
        if (!pending.persisted) {
          await chat.saveControlLocally(
            SendNotConfirmedException(
              outcome: SendOutcome.publishedLocalSaveFailed,
              chatId: chatId,
              messageId: pending.messageId,
              body: '',
              attemptedAt: pending.attemptedAt,
              persisted: false,
              mutation: pending.mutation,
            ),
          );
        }
      }
    });
  }
}

final messageControlsProvider = NotifierProvider.autoDispose
    .family<MessageControls, MessageControlState, String>(MessageControls.new);
