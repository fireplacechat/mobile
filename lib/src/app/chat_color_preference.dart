import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/settings/account_preferences.dart';
import 'package:fireplace/src/styles/chat_colors.dart';

/// The account's local chat colours; other accounts keep their own choices.
class ChatAppearance extends Notifier<ChatBubbleColors> {
  static const storageKey = 'ui:chat-colors';
  Future<void> _writes = Future.value();
  Future<void> _loaded = Future.value();
  bool _chosen = false, _saved = false;
  int _epoch = 0;

  /// Completes when the saved choice has been read (or found unreadable).
  Future<void> get loaded => _loaded;

  @override
  ChatBubbleColors build() {
    _chosen = false;
    _saved = false;
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
      _saved = true;
      state = ChatBubbleColors.parse(saved);
    } catch (_) {
      // Unreadable colours must not prevent opening the app.
    }
  }

  /// Each of these shows the choice at once and completes when it is saved.
  /// If saving fails the future fails; the choice still lasts until the app
  /// closes.
  Future<void> outgoing(ChatBubbleColor color) =>
      _choose(ChatBubbleColors(outgoing: color));
  Future<void> reset() => _choose(const ChatBubbleColors());

  /// Takes the colour on this account's profile when this phone has none of
  /// its own: one chosen on another phone (decision 0053).
  void adopt(ChatBubbleColor published) {
    if (_chosen || _saved) return;
    state = ChatBubbleColors(outgoing: published);
  }

  Future<void> _choose(ChatBubbleColors colors) {
    _chosen = true;
    state = colors;
    // On the profile, for the people this account chats with. A failure is
    // not shown: the choice still holds here, and Firestore sends a write
    // made offline when it can.
    final chat = ref.read(appSessionProvider).value?.chat;
    if (chat != null) {
      unawaited(
        chat.publishColor(colors.outgoing.name).catchError((Object _) {}),
      );
    }
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

/// The colour another person chose, read from their profile (decision 0053),
/// or null when it is not known.
final knownPeerColorProvider = Provider.autoDispose
    .family<ChatBubbleColor?, String>((ref, peerUid) {
      final peers = ref.watch(appSessionProvider).value?.peerColors;
      if (peers == null) return null;
      final changes = peers.changes.listen((changed) {
        if (changed == peerUid) ref.invalidateSelf();
      });
      ref.onDispose(changes.cancel);
      return ChatBubbleColor.values.asNameMap()[peers.of(peerUid)];
    });

/// The colour to show another person's 1:1 messages in: the one they chose,
/// or the default when it is not known.
final peerColorProvider = Provider.autoDispose.family<ChatBubbleColor, String>(
  (ref, peerUid) =>
      ref.watch(knownPeerColorProvider(peerUid)) ?? ChatBubbleColors.unknown,
);

/// The colour a person's avatar and name are shown in: their own, once the
/// chat with them is accepted. Null (the app's usual look) before that, and
/// while their colour is not known.
final acceptedPeerColorProvider = Provider.autoDispose
    .family<ChatBubbleColor?, String>((ref, peerUid) {
      final accepted = ref.watch(
        chatsProvider.select(
          (chats) =>
              chats.value?.any((c) => c.peerUid == peerUid && c.accepted) ??
              false,
        ),
      );
      return accepted ? ref.watch(knownPeerColorProvider(peerUid)) : null;
    });
