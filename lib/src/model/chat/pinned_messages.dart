import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/providers.dart';

/// Device-local pins for the signed-in account. Empty after sign-out.
class PinnedMessages extends Notifier<Map<String, List<String>>> {
  @override
  Map<String, List<String>> build() {
    final session = ref.watch(appSessionProvider).value;
    if (session == null) return const {};
    final prefs = session.chatPreferences;
    final sub = prefs.changes.listen((_) {
      if (ref.mounted) state = _copy(prefs.pinned);
    });
    ref.onDispose(sub.cancel);
    return _copy(prefs.pinned);
  }

  Future<void> toggle(String chatId, String messageId) {
    final session = ref.read(appSessionProvider).value;
    if (session == null) return Future.value();
    return session.chatPreferences.togglePin(chatId, messageId);
  }

  static Map<String, List<String>> _copy(Map<String, List<String>> source) => {
    for (final entry in source.entries) entry.key: List<String>.of(entry.value),
  };
}

final pinnedMessagesProvider =
    NotifierProvider<PinnedMessages, Map<String, List<String>>>(
      PinnedMessages.new,
    );
