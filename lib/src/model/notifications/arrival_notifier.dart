import 'dart:async';

import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/db/secret_store.dart';
import 'package:fireplace/src/model/notifications/notification_preview.dart';
import 'package:fireplace/src/model/notifications/preview_notifier.dart';
import 'package:fireplace/src/model/push/push_notification_service.dart';

/// While the app is alive but not on screen, its own listeners may receive a
/// message before the push handler does; the handler then finds nothing new.
/// So the app posts what it received itself (decision 0030). On screen, the
/// in-app notice shows arrivals instead.
class ArrivalNotifier {
  ArrivalNotifier({
    required Stream<LocalMessage> arrivals,
    required this.uid,
    required this.prefs,
    required this.store,
    required this.notifier,
    required this.onScreen,
    required this.usernameOf,
  }) {
    _sub = arrivals.listen((m) => _work = _work.then((_) => _post(m)));
  }

  final String uid;
  final SecretStore prefs;
  final LocalMessageStore store;
  final PreviewNotifier notifier;

  /// True while the app is in the foreground.
  final bool Function() onScreen;

  /// The other person's username in a chat, or null.
  final Future<String?> Function(String chatId) usernameOf;

  late final StreamSubscription<LocalMessage> _sub;
  Future<void> _work = Future.value();

  Future<void> _post(LocalMessage message) async {
    try {
      if (onScreen()) return;
      final choices = await PushChoices.read(prefs, uid);
      // With previews off the push's own plain alert is shown, exactly as
      // before previews; posting here too would sound twice.
      if (!choices.alerts || !choices.preview) return;
      final name = choices.showName ? await usernameOf(message.chatId) : null;
      await notifier.arrived(
        message,
        store: store,
        ownUid: uid,
        title: notificationTitle(
          username: name ?? '',
          showName: choices.showName,
        ),
        showPreview: choices.preview,
        channel: choices.channel,
      );
    } catch (_) {
      // A notification is never worth an error.
    }
  }

  Future<void> close() async {
    await _sub.cancel();
    await _work;
  }
}
