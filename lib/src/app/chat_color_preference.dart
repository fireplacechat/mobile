import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/settings/account_preferences.dart';
import 'package:fireplace/src/styles/chat_colors.dart';

/// The account's local chat colours; other accounts keep their own choices.
class ChatAppearance extends Notifier<ChatBubbleColors> {
  static const storageKey = 'ui:chat-colors';
  Future<void> _writes = Future.value();
  Future<void> _loaded = Future.value();
  bool _chosen = false;
  int _epoch = 0;

  /// Completes when the saved choice has been read (or found unreadable).
  Future<void> get loaded => _loaded;

  @override
  ChatBubbleColors build() {
    _chosen = false;
    _loaded = _load(
      ref.watch(accountPreferencesProvider),
      ref.watch(preferencesUidProvider),
      ++_epoch,
    );
    // The defaults show for the moment the saved choice takes to read.
    return const ChatBubbleColors();
  }

  Future<void> _load(AccountPreferences store, String? uid, int epoch) async {
    try {
      final saved = await store.read(storageKey, uid);
      // A choice made while the saved one was loading wins.
      if (!ref.mounted || _epoch != epoch || _chosen || saved == null) return;
      state = ChatBubbleColors.parse(saved);
    } catch (_) {
      // Unreadable colours must not prevent opening the app.
    }
  }

  /// Each of these shows the choice at once and completes when it is saved.
  /// If saving fails the future fails; the choice still lasts until the app
  /// closes.
  Future<void> outgoing(ChatBubbleColor color) =>
      _choose(ChatBubbleColors(outgoing: color, incoming: state.incoming));
  Future<void> incoming(ChatBubbleColor color) =>
      _choose(ChatBubbleColors(outgoing: state.outgoing, incoming: color));
  Future<void> reset() => _choose(const ChatBubbleColors());

  Future<void> _choose(ChatBubbleColors colors) {
    _chosen = true;
    state = colors;
    final store = ref.read(accountPreferencesProvider);
    final uid = ref.read(preferencesUidProvider);
    final write = _writes.then(
      (_) => store.write(storageKey, uid, colors.stored),
    );
    // Save choices in order, and allow another after a failed save.
    _writes = write.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return write;
  }
}

final chatBubbleColorsProvider =
    NotifierProvider<ChatAppearance, ChatBubbleColors>(ChatAppearance.new);
