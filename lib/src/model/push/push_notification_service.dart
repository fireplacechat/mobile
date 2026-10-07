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
  int _generation = 0;
  Future<void> _registrationWork = Future.value();
  Future<void> _deletionWork = Future.value();

  /// Turns notifications on, asking the OS for permission if needed. Call this
  /// from an explicit user action (a settings switch), not at launch.
  Future<void> start() => _startFuture ??= _start();

  /// Re-registers silently on later launches, only if the user already agreed.
  Future<void> startIfPermitted() async {
    if (_startFuture != null) return _startFuture!;
    final gen = _generation;
    final permitted = await _messaging.hasPermission();
    if (!permitted || _stopped || gen != _generation) return;
    return start();
  }

  Future<void> _start() async {
    final gen = ++_generation;
    if (_stopped) return;
    await _messaging.setForegroundPresentation();
    if (gen != _generation) return;
    final allowed = await _messaging.requestPermission();
    if (gen != _generation) return;
    if (!allowed) {
      await _deleteRegistration();
      return;
    }

    _tokenSubscription = _messaging.onTokenRefresh.listen(
      (token) => unawaited(_saveWhenReady(token, gen)),
      onError: (Object _) {},
    );
    final token = await _messaging.getToken();
    if (gen != _generation) return;
    if (token != null) await _saveWhenReady(token, gen);
  }

  Future<void> _saveWhenReady(String token, int gen) async {
    if (_stopped || gen != _generation || token.isEmpty) return;
    if (_isApplePlatform && !await _hasApnsToken(gen)) return;
    if (gen != _generation) return;
    // Finish an old write and its compensating delete before a new generation
    // writes its token. Otherwise old cleanup could erase the restarted record.
    _registrationWork = _registrationWork.then((_) async {
      await _deletionWork;
      if (gen != _generation) return;
      try {
        await _tokenRef.set({
          'token': token,
          'platform': _platform,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        // A write already sent cannot be cancelled; remove its stale result.
        if (gen != _generation) await _deleteRegistration();
      } catch (_) {
        // Push is optional; a transient Firestore failure must not block chat.
      }
    });
    await _registrationWork;
  }

  Future<bool> _hasApnsToken(int gen) async {
    final deadline = DateTime.now().add(_apnsTokenWait);
    do {
      if (_stopped || gen != _generation) return false;
      final token = await _messaging.getApnsToken();
      if (gen != _generation) return false;
      if (token != null) return true;
      if (DateTime.now().isAfter(deadline)) break;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    } while (!_stopped && gen == _generation);
    return false;
  }

  /// True when notifications are allowed by the OS and this device is registered.
  Future<bool> isOn() async =>
      !_stopped &&
      await _messaging.hasPermission() &&
      (await _tokenRef.get()).exists;

  /// Turns notifications off for this device but keeps the service reusable.
  Future<void> disable() async {
    final gen = ++_generation;
    final subscription = _tokenSubscription;
    _tokenSubscription = null;
    _startFuture = null;
    await subscription?.cancel();
    if (gen == _generation) await _deleteRegistration();
  }

  /// Removes this account's routing record before an explicit sign-out.
  Future<void> unregister() async {
    _generation++;
    if (_stopped) return;
    _stopped = true;
    final subscription = _tokenSubscription;
    _tokenSubscription = null;
    _startFuture = null;
    await subscription?.cancel();
    await _deleteRegistration();
  }

  Future<void> _deleteRegistration() => _deletionWork = _deletionWork.then((
    _,
  ) async {
    try {
      await _tokenRef.delete();
    } catch (_) {
      // Cleanup is best-effort. The account/session transition must continue.
    }
  });
}
