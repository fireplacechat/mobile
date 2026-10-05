import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/services/chat_service.dart';

/// If even encrypted history saving fails, keep the warning across local routes.
/// Account-scoped memory only; no server writes or automatic publishing.
class PendingLocalSends
    extends Notifier<Map<String, SendNotConfirmedException>> {
  @override
  Map<String, SendNotConfirmedException> build() {
    ref.watch(appSessionProvider.select((s) => s.value?.uid));
    return {};
  }

  String _key(String chat, String id) => '$chat/$id';
  void add(SendNotConfirmedException send, {required String ownerUid}) {
    if (!ref.mounted || ref.read(appSessionProvider).value?.uid != ownerUid) {
      return;
    }
    state = {...state, _key(send.chatId, send.messageId): send};
  }

  void confirmed(String chat, String id, {required String ownerUid}) {
    if (!ref.mounted) return;
    final old = state[_key(chat, id)];
    if (old == null) return;
    add(
      SendNotConfirmedException(
        outcome: SendOutcome.publishedLocalSaveFailed,
        chatId: old.chatId,
        messageId: old.messageId,
        body: old.body,
        attemptedAt: old.attemptedAt,
        persisted: false,
      ),
      ownerUid: ownerUid,
    );
  }

  void remove(String chat, String id) {
    final next = {...state}..remove(_key(chat, id));
    if (next.length != state.length) state = next;
  }
}

final pendingLocalSendsProvider =
    NotifierProvider<PendingLocalSends, Map<String, SendNotConfirmedException>>(
      PendingLocalSends.new,
    );
