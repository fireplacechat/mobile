import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/chat/message_limits.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const maxChatDrafts = 32;

/// Keeps recent unsent text across routes, only for the current account in memory.
class ChatDrafts extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() {
    ref.watch(appSessionProvider.select((session) => session.value?.uid));
    return const {};
  }

  bool _owns(String? ownerUid) =>
      ref.mounted &&
      ownerUid != null &&
      ref.read(appSessionProvider).value?.uid == ownerUid;

  String textFor(String chatId, {required String? ownerUid}) =>
      _owns(ownerUid) ? state[chatId] ?? '' : '';

  void save(String chatId, String text, {required String? ownerUid}) {
    if (!_owns(ownerUid)) return;
    final bounded = clipMessage(text, maxMessageCharacters);
    if ((state[chatId] ?? '') == bounded) return;
    final next = {...state}..remove(chatId);
    if (bounded.isNotEmpty) {
      if (next.length >= maxChatDrafts) next.remove(next.keys.first);
      next[chatId] = bounded;
    }
    state = Map.unmodifiable(next);
  }
}

final chatDraftsProvider = NotifierProvider<ChatDrafts, Map<String, String>>(
  ChatDrafts.new,
);
