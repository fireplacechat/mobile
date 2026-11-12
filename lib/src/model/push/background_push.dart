import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/db/secret_store.dart';
import 'package:fireplace/src/model/chat/chat_service.dart';
import 'package:fireplace/src/model/notifications/notification_preview.dart';
import 'package:fireplace/src/model/notifications/preview_notifier.dart';
import 'package:fireplace/src/model/push/push_chat_index.dart';
import 'package:fireplace/src/model/push/push_notification_service.dart';

/// The stores and chat service a background run opens for one account.
class BackgroundSession {
  BackgroundSession({
    required this.chat,
    required this.store,
    required this.close,
  });
  final ChatService chat;
  final LocalMessageStore store;
  final Future<void> Function() close;
}

/// What the background push handler does with a data push (decision 0030):
/// find the chat, receive its new messages with the app's own code, and post
/// what arrived; "New Message" whenever that cannot be done in time. Never
/// sends, publishes or refills prekeys.
class BackgroundPush {
  BackgroundPush({
    required this.uid,
    required this.prefs,
    required this.notifier,
    required this.open,
    this.limit = const Duration(seconds: 8),
    this.fetch = const GetOptions(source: Source.server),
  });

  /// The signed-in account, or null.
  final String? uid;

  /// This device's choices and the chat index (the secure store).
  final SecretStore prefs;
  final PreviewNotifier notifier;

  /// Opens this account's stores, under the account lock shared with the app.
  final Future<BackgroundSession> Function(String uid) open;

  /// Android gives a high-priority push a few seconds.
  final Duration limit;
  final GetOptions fetch;

  /// Handles one push's data. Never throws.
  Future<void> handle(Map<String, String> data) async {
    if (data['fp'] != '1') return;
    final key = data['k'];
    if (key == null || key.isEmpty) return;
    final title = data['title'] ?? hiddenNotificationTitle;
    final channel = data['ch'] == 'messages_silent'
        ? 'messages_silent'
        : 'messages';
    Future<void> plain() => notifier
        .plain(tag: key, title: title, channel: channel)
        .catchError((Object _) {});

    final account = uid;
    if (account == null) return plain();
    final PushChoices choices;
    final String? chatId;
    try {
      choices = await PushChoices.read(prefs, account);
      if (!choices.alerts) return; // turned off in Fireplace
      if (!choices.preview) return await plain(); // exactly as before previews
      chatId = await PushChatIndex(prefs, account).chatFor(key);
    } catch (_) {
      return plain();
    }
    if (chatId == null) return plain();

    var shown = false;
    final work = _receive(account, chatId, title, channel, () => shown = true);
    try {
      final finished = await work.timeout(limit);
      if (!finished && !shown) await plain();
    } catch (_) {
      // Timed out, offline, or the stores could not open. What arrives
      // later on this run is still shown.
      if (!shown) await plain();
    }
  }

  Future<bool> _receive(
    String account,
    String chatId,
    String title,
    String channel,
    void Function() onShown,
  ) async {
    final session = await open(account);
    final posts = <Future<void>>[];
    final sub = session.chat.arrivals.listen((message) {
      posts.add(() async {
        try {
          if (await notifier.arrived(
            message,
            store: session.store,
            ownUid: account,
            title: title,
            showPreview: true,
            channel: channel,
          )) {
            onShown();
          }
        } catch (_) {
          // The next push or the app shows it.
        }
      }());
    });
    try {
      final finished = await session.chat.receiveOnce(
        chatId,
        options: fetch,
        upkeep: false,
      );
      await Future<void>.delayed(Duration.zero); // deliver the last arrival
      await Future.wait(posts);
      return finished;
    } finally {
      await sub.cancel();
      await session.close();
    }
  }
}
