import 'package:fireplace_native/fireplace_native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/model/notifications/notification_preview.dart';

/// Where notifications go. The Android plugin in the app; a fake in tests.
abstract interface class NotificationPoster {
  Future<void> show({
    required String tag,
    required String title,
    required String body,
    required String messageId,
    required String channel,
    bool silent = false,
  });
  Future<void> remove(String tag);

  /// Tag -> message id of each alert still on screen.
  Future<Map<String, String>> showing();
}

/// Posts through `packages/fireplace_native`. A notification is never worth
/// an error: a missing plugin (tests, iOS) or a refusal is ignored.
class NativeNotificationPoster implements NotificationPoster {
  const NativeNotificationPoster([
    this._native = const FireplaceNotifications(),
  ]);
  final FireplaceNotifications _native;

  Future<T?> _guard<T>(String what, Future<T> Function() call) async {
    try {
      return await call();
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('notifications: $what failed (${e.code})');
      return null;
    }
  }

  @override
  Future<void> show({
    required String tag,
    required String title,
    required String body,
    required String messageId,
    required String channel,
    bool silent = false,
  }) => _guard(
    'show',
    () => _native.show(
      tag: tag,
      title: title,
      body: body,
      messageId: messageId,
      channel: channel,
      silent: silent,
    ),
  );

  @override
  Future<void> remove(String tag) =>
      _guard('remove', () => _native.remove(tag));

  @override
  Future<Map<String, String>> showing() async =>
      await _guard('showing', _native.showing) ?? const {};
}

/// Turns received messages into notifications (decision 0030), in the
/// formats of [notificationChanges]. The plugin updates an alert posted under
/// the same tag in the last 20 seconds silently, whichever isolate posted it,
/// as the server's throttle allows one push per conversation every 20 s.
class PreviewNotifier {
  PreviewNotifier(this._poster);

  final NotificationPoster _poster;

  /// Shows what [arrived] means for its conversation. [store] gives the
  /// message a reaction, edit or delete refers to. True if anything changed.
  Future<bool> arrived(
    LocalMessage arrived, {
    required LocalMessageStore store,
    required String ownUid,
    required String title,
    required bool showPreview,
    required String channel,
  }) async {
    final targetId = arrived.mutation?.targetId;
    final changes = notificationChanges(
      arrived: arrived,
      target: targetId == null
          ? null
          : await store.get(arrived.chatId, targetId),
      ownUid: ownUid,
      conversationKey: await conversationKey(arrived.chatId),
      title: title,
      showPreview: showPreview,
      showing: arrived.mutation == null ? const {} : await _poster.showing(),
    );
    for (final change in changes) {
      switch (change) {
        case ShowNotification():
          await _show(change, channel);
        case RemoveNotification():
          await _poster.remove(change.tag);
      }
    }
    return changes.isNotEmpty;
  }

  /// The plain alert, when what arrived is unknown.
  Future<void> plain({
    required String tag,
    required String title,
    required String channel,
  }) => _show(
    ShowNotification(
      tag: tag,
      title: title,
      body: plainNotificationBody,
      messageId: '',
    ),
    channel,
  );

  Future<void> _show(ShowNotification change, String channel) => _poster.show(
    tag: change.tag,
    title: change.title,
    body: change.body,
    messageId: change.messageId,
    channel: channel,
    silent: change.silent,
  );
}
