// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// Push notifications are compiled in but OFF unless the app is built with
/// `--dart-define=PUSH_ENABLED=true`. They need a server-side sender and Apple
/// push capability first (see docs/push/README.md).
const pushEnabled = bool.fromEnvironment('PUSH_ENABLED');

/// Small seam around the platform plugin so token lifecycle can be unit tested.
abstract interface class PushMessagingClient {
  /// True if the user already allowed notifications (never shows a prompt).
  Future<bool> hasPermission();
  Future<bool> requestPermission();
  Future<String?> getApnsToken();
  Future<String?> getToken();
  Stream<String> get onTokenRefresh;
  Future<void> setForegroundPresentation();
}

class FirebasePushMessagingClient implements PushMessagingClient {
  FirebasePushMessagingClient([FirebaseMessaging? messaging])
    : _messaging = messaging ?? FirebaseMessaging.instance;

  final FirebaseMessaging _messaging;

  @override
  Future<bool> hasPermission() async {
    final settings = await _messaging.getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: false,
      sound: true,
    );
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<String?> getApnsToken() => _messaging.getAPNSToken();

  @override
  Future<String?> getToken() => _messaging.getToken();

  @override
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  @override
  Future<void> setForegroundPresentation() =>
      _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: false,
        sound: true,
      );
}

/// Registers this signed-in installation for generic, ciphertext-free alerts.
/// The registration lives under the account/device pair and is owner-readable.
class PushNotificationService {
  PushNotificationService({
    required FirebaseFirestore db,
    required String uid,
    required String deviceId,
    required PushMessagingClient messaging,
    bool? isApplePlatform,
    String? platform,
    Duration apnsTokenWait = const Duration(seconds: 5),
  }) : _messaging = messaging,
       _isApplePlatform = isApplePlatform ?? Platform.isIOS,
       _platform = platform ?? (Platform.isIOS ? 'ios' : 'android'),
       _apnsTokenWait = apnsTokenWait,
       _tokenRef = db
           .collection('users')
           .doc(uid)
           .collection('pushTokens')
           .doc(deviceId);

  final PushMessagingClient _messaging;
  final bool _isApplePlatform;
  final String _platform;
  final Duration _apnsTokenWait;
  final DocumentReference<Map<String, dynamic>> _tokenRef;
  StreamSubscription<String>? _tokenSubscription;
  Future<void>? _startFuture;
  bool _stopped = false;

  /// Turns notifications on, asking the OS for permission if needed. Call this
  /// from an explicit user action (a settings switch), not at launch.
  Future<void> start() => _startFuture ??= _start();

  /// Re-registers silently on later launches, only if the user already agreed.
  Future<void> startIfPermitted() async {
    if (_startFuture != null) return _startFuture!;
    if (!await _messaging.hasPermission()) return;
    return start();
  }

  Future<void> _start() async {
    if (_stopped) return;
    await _messaging.setForegroundPresentation();
    final allowed = await _messaging.requestPermission();
    if (!allowed) {
      await _deleteRegistration();
      return;
    }

    _tokenSubscription = _messaging.onTokenRefresh.listen(
      (token) => unawaited(_saveWhenReady(token)),
      onError: (Object _) {},
    );
    final token = await _messaging.getToken();
    if (token != null) await _saveWhenReady(token);
  }

  Future<void> _saveWhenReady(String token) async {
    if (_stopped || token.isEmpty) return;
    if (_isApplePlatform && !await _hasApnsToken()) return;
    try {
      await _tokenRef.set({
        'token': token,
        'platform': _platform,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Push is optional; a transient Firestore failure must not block chat.
    }
  }

  Future<bool> _hasApnsToken() async {
    final deadline = DateTime.now().add(_apnsTokenWait);
    do {
      if (await _messaging.getApnsToken() != null) return true;
      if (DateTime.now().isAfter(deadline)) break;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    } while (!_stopped);
    return false;
  }

  /// True when notifications are allowed by the OS and this device is registered.
  Future<bool> isOn() async =>
      !_stopped &&
      await _messaging.hasPermission() &&
      (await _tokenRef.get()).exists;

  /// Turns notifications off for this device but keeps the service reusable.
  Future<void> disable() async {
    await _tokenSubscription?.cancel();
    _tokenSubscription = null;
    _startFuture = null;
    await _deleteRegistration();
  }

  /// Removes this account's routing record before an explicit sign-out.
  Future<void> unregister() async {
    if (_stopped) return;
    _stopped = true;
    await _tokenSubscription?.cancel();
    await _deleteRegistration();
  }

  Future<void> _deleteRegistration() async {
    try {
      await _tokenRef.delete();
    } catch (_) {
      // Cleanup is best-effort. The account/session transition must continue.
    }
  }
}
