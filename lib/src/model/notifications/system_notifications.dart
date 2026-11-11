import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final systemNotificationsProvider = Provider<SystemNotifications>(
  (_) => const ChannelSystemNotifications(),
);

/// The parts of the operating system's notification features that no plugin
/// covers: the app icon badge, clearing delivered alerts, opening the system
/// notification settings for Fireplace, and the send sound. Implemented natively in
/// `ios/Runner/AppDelegate.swift` and `android/.../MainActivity.kt`.
abstract interface class SystemNotifications {
  /// Sets the red number on the app icon. 0 removes it. iOS only; Android
  /// launchers show a dot while a notification is in the shade.
  Future<void> setBadge(int count);

  /// Removes Fireplace alerts already shown in Notification Center / the shade.
  Future<void> clearDelivered();

  /// Opens Fireplace's page in the system notification settings.
  Future<void> openSettings();

  /// Plays the short send pop. Silent when the phone is set to silent.
  Future<void> playSendSound();
}

class ChannelSystemNotifications implements SystemNotifications {
  const ChannelSystemNotifications();

  static const _channel = MethodChannel('fireplace/notifications');

  // Badges and settings are conveniences. A missing native side (tests, an
  // unsupported platform) or an OS refusal must never surface as an error.
  Future<void> _call(String method, [Object? args]) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      // not available on this platform
    } on PlatformException catch (e) {
      debugPrint('notifications: $method failed (${e.code})');
    }
  }

  @override
  Future<void> setBadge(int count) => _call('setBadge', count < 0 ? 0 : count);

  @override
  Future<void> clearDelivered() => _call('clearDelivered');

  @override
  Future<void> openSettings() => _call('openSettings');

  @override
  Future<void> playSendSound() => _call('playSendSound');
}
