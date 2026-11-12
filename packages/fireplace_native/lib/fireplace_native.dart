import 'package:flutter/services.dart';

/// Fireplace's own notifications on Android, available in every Flutter
/// engine, including the background push handler's (app decision 0030).
class FireplaceNotifications {
  const FireplaceNotifications();

  static const _channel = MethodChannel('fireplace/native_notifications');

  /// Shows an alert under [tag], replacing the one there. [messageId] is kept
  /// with it for [showing]. [silent] updates without a sound or banner if an
  /// alert is already showing under [tag].
  Future<void> show({
    required String tag,
    required String title,
    required String body,
    required String messageId,
    required String channel,
    bool silent = false,
  }) => _channel.invokeMethod<void>('show', {
    'tag': tag,
    'title': title,
    'body': body,
    'messageId': messageId,
    'channel': channel,
    'silent': silent,
  });

  Future<void> remove(String tag) =>
      _channel.invokeMethod<void>('remove', {'tag': tag});

  /// Tag -> message id of each Fireplace alert still on screen.
  Future<Map<String, String>> showing() async {
    final raw = await _channel.invokeMapMethod<String, String>('showing');
    return raw ?? const {};
  }
}
