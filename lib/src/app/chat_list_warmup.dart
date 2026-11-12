import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/chat/chat_service.dart';

/// The longest launch keeps the loading screen up for the chat list. On a
/// slow or missing network the list appears anyway and fills in as it can.
const chatListWarmupLimit = Duration(seconds: 3);

/// How many conversations, newest first, are loaded before the list shows:
/// a little more than a tall phone fits on one screen. Rows further down
/// load when they are scrolled to, as before.
const chatListWarmupRows = 12;

/// Completes when the chat list can be shown without placeholders: the
/// conversations, the block and hide lists, and for the top rows the
/// username (which also gives the avatar its initial) and the local history
/// the preview line comes from.
///
/// It reads nothing the list would not read itself, so it adds no Firestore
/// reads; it only starts them while the loading screen is still up. It never
/// fails: an error is left for the chat list, which already explains it.
final chatListWarmupProvider = FutureProvider.autoDispose<void>((ref) async {
  final session = ref.watch(appSessionProvider).value;
  if (session == null) return;
  // `listen` rather than `watch`: a new message must not bring the loading
  // screen back. Listening also keeps the auto-disposed providers alive, so
  // the chat list finds them loaded instead of starting again.
  Future<T> hold<T>(ProviderListenable<Future<T>> provider) =>
      ref.listen(provider, (_, _) {}).read();
  try {
    await _warm(session.uid, hold).timeout(chatListWarmupLimit);
  } catch (_) {
    // A timeout or an error: show the list, which shows its own state.
  }
});

Future<void> _warm(
  String me,
  Future<T> Function<T>(ProviderListenable<Future<T>>) hold,
) async {
  final (chats, blocked, hidden, _) = await (
    hold(chatsProvider.future),
    hold(blockedUidsProvider.future),
    hold(hiddenChatsProvider.future),
    hold(identityAlertsProvider.future),
  ).wait;
  await [
    for (final chat in firstChatRows(chats, me, blocked, hidden)) ...[
      hold(peerUsernameProvider(chat.peerUid).future),
      hold(messagesProvider(chat.chatId).future),
    ],
  ].wait;
}

/// The conversations at the top of the chat list, in the order the list
/// shows them. Requests are left out: the list shows them as one row.
List<ChatSummary> firstChatRows(
  List<ChatSummary> chats,
  String me,
  Set<String> blocked,
  Set<String> hidden,
) {
  final epoch = DateTime.fromMillisecondsSinceEpoch(0);
  final shown = [
    for (final c in chats)
      if (!blocked.contains(c.peerUid) &&
          !hidden.contains(c.chatId) &&
          !c.isIncomingRequest(me))
        c,
  ];
  shown.sort(
    (a, b) => (b.lastMessageAt ?? epoch).compareTo(a.lastMessageAt ?? epoch),
  );
  return shown.take(chatListWarmupRows).toList();
}
