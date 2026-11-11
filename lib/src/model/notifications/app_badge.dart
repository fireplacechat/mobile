import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/notifications/chat_activity.dart';
import 'package:fireplace/src/model/notifications/system_notifications.dart';

/// Keeps the app icon badge equal to this device's unread total (muted chats
/// excluded). The count comes from the encrypted local history; the server
/// never learns what was read. Watch it once near the root of the app.
///
/// When the total reaches zero, delivered "New Message" alerts are cleared
/// too: they would otherwise point at messages that have been read.
final appBadgeProvider = Provider<void>((ref) {
  final system = ref.watch(systemNotificationsProvider);
  int? shown;
  void update() {
    final count = appBadgeCount(
      ref.read(appSessionProvider),
      ref.read(chatActivityProvider),
    );
    if (count == null || count == shown) return;
    shown = count;
    unawaited(system.setBadge(count));
    if (count == 0) unawaited(system.clearDelivered());
  }

  ref.listen(appSessionProvider, (_, _) => update());
  ref.listen(chatActivityProvider, (_, _) => update(), fireImmediately: true);
});

/// The badge to show, or null to leave it as it is. While the session is
/// starting (or failed) or history is still loading, the old badge stays:
/// dropping it to zero at every launch would also clear unseen alerts.
int? appBadgeCount(AsyncValue<Object?> session, ChatActivityState activity) {
  if (session.isLoading || session.hasError) return null;
  if (session.value == null) return 0; // signed out
  if (activity.loading) return null;
  return activity.badgeCount;
}
