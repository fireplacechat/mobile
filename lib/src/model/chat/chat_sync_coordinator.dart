import 'dart:async';

import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/model/safety/safety_service.dart';
import 'package:fireplace/src/model/settings/local_chat_preferences.dart';
import 'package:fireplace/src/services/chat_service.dart';

class ChatSyncCoordinator {
  ChatSyncCoordinator({
    required this.uid,
    required this.safety,
    required this.chat,
    required this.chatPreferences,
    required this.store,
    required this.isStopped,
  });

  final String uid;
  final SafetyService safety;
  final ChatService chat;
  final LocalChatPreferences chatPreferences;
  final LocalMessageStore store;
  final bool Function() isStopped;
  final _syncs = <String, StreamSubscription<void>>{};
  var _latest = <ChatSummary>[];

  void chatsChanged(List<ChatSummary> chats) {
    _latest = chats;
    unawaited(reconcile().catchError((Object _) {}));
  }

  void blockedChanged() {
    unawaited(reconcile().catchError((Object _) {}));
  }

  Future<void> reconcile() async {
    if (isStopped()) return;
    final hidden = await safety.hiddenChats();
    if (isStopped()) return;
    final wanted = <String>{
      for (final c in _latest)
        if (!c.isIncomingRequest(uid) &&
            !safety.isBlocked(c.peerUid) &&
            !hidden.contains(c.chatId))
          c.chatId,
    };
    for (final id in _syncs.keys.toList()) {
      if (!wanted.contains(id)) await _syncs.remove(id)?.cancel();
    }
    for (final id in wanted) {
      if (isStopped()) return;
      if (chatPreferences.available && chatPreferences.needsBaseline(id)) {
        try {
          // Capture disk history before starting receive sync. Later network
          // arrivals must not be swallowed by first-run read bookkeeping.
          final existing = await store.watch(id).first;
          await chatPreferences.seedExisting(
            id,
            existing.where((m) => !m.outgoing).map((m) => m.id),
          );
        } catch (_) {
          // A broken UI sidecar does not stop messaging; Settings offers reset.
        }
      }
      // Baseline I/O may have yielded to a block, hide, request change or disposal.
      final nowHidden = await safety.hiddenChats();
      if (isStopped()) return;
      if (!_latest.any(
            (c) =>
                c.chatId == id &&
                !c.isIncomingRequest(uid) &&
                !safety.isBlocked(c.peerUid),
          ) ||
          nowHidden.contains(id)) {
        continue;
      }
      _syncs.putIfAbsent(id, () => chat.startSync(id));
    }
  }

  Future<void> stop() async {
    for (final sub in _syncs.values.toList()) {
      await sub.cancel();
    }
    _syncs.clear();
  }
}
