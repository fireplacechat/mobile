// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:fireplace/src/db/secret_store.dart';

/// Push notifications are on in normal builds. Build with
/// `--dart-define=PUSH_ENABLED=false` to compile them out (for example a build
/// signed without the push entitlement). The sender is the `pushOnMessage`
/// Cloud Function in the backend repository; see docs/decisions/0026.
const pushEnabled = bool.fromEnvironment('PUSH_ENABLED', defaultValue: true);

/// The operating system's answer about notifications, read without prompting.
enum PushPermission { notDetermined, allowed, denied }

/// What the settings screen shows for this device.
enum PushStatus {
  /// Allowed by the system and registered for alerts.
  on,

  /// Turned off in Fireplace, or not registered yet.
  off,

  /// Turned off in the system settings; only the user can change that there.
  blockedBySystem,
}

/// Small seam around the platform plugin so token lifecycle can be unit tested.
abstract interface class PushMessagingClient {
  /// Reads the current permission. Never shows a prompt.
  Future<PushPermission> permissionStatus();

  /// Shows the system prompt if the system still allows one; otherwise returns
  /// the stored answer. True when alerts are allowed.
  Future<bool> requestPermission();
  Future<String?> getApnsToken();
  Future<String?> getToken();
  Stream<String> get onTokenRefresh;
  Future<void> setForegroundPresentation();
}

class FirebasePushMessagingClient implements PushMessagingClient {
  FirebasePushMessagingClient([FirebaseMessaging? messaging])
    : _injected = messaging;

  final FirebaseMessaging? _injected;
  FirebaseMessaging get _messaging => _injected ?? FirebaseMessaging.instance;

  static bool _allowed(AuthorizationStatus s) =>
      s == AuthorizationStatus.authorized ||
      s == AuthorizationStatus.provisional;

  @override
  Future<PushPermission> permissionStatus() async {
    final status =
        (await _messaging.getNotificationSettings()).authorizationStatus;
    if (_allowed(status)) return PushPermission.allowed;
    if (status == AuthorizationStatus.notDetermined) {
      return PushPermission.notDetermined;
    }
    return PushPermission.denied;
  }

  @override
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    return _allowed(settings.authorizationStatus);
  }

  @override
  Future<String?> getApnsToken() => _messaging.getAPNSToken();

  @override
  Future<String?> getToken() => _messaging.getToken();

  @override
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  // While Fireplace is open the in-app notice shows arrivals (with the user's
  // preview choice), so a system banner on top would be a duplicate. The badge
  // is managed by the app (AppBadge), never by a push.
  @override
  Future<void> setForegroundPresentation() =>
      _messaging.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: false,
        sound: false,
      );
}

/// Registers this signed-in installation for alerts that show the sender's
/// username and "New Message", never message text. The registration lives under
/// the account/device pair and is owner-readable.
class PushNotificationService {
  PushNotificationService({
    required FirebaseFirestore db,
    required String uid,
    required String deviceId,
    required PushMessagingClient messaging,
    SecretStore? preferences,
    bool? isApplePlatform,
    String? platform,
    Duration apnsTokenWait = const Duration(seconds: 5),
  }) : _messaging = messaging,
       _prefs = preferences ?? MemorySecretStore(),
       _optOutKey = 'pushoff:$uid',
       _askedKey = 'pushasked:$uid',
       _hideNameKey = 'pushhidename:$uid',
       _silentKey = 'pushsilent:$uid',
       _isApplePlatform = isApplePlatform ?? Platform.isIOS,
       _platform = platform ?? (Platform.isIOS ? 'ios' : 'android'),
       _apnsTokenWait = apnsTokenWait,
       _tokenRef = db
           .collection('users')
           .doc(uid)
           .collection('pushTokens')
           .doc(deviceId);

  final PushMessagingClient _messaging;
  // Device-local choices. They are not secrets, but this store is already
  // per-install, survives restarts and is wiped with the account.
  final SecretStore _prefs;
  final String _optOutKey, _askedKey, _hideNameKey, _silentKey;
  final bool _isApplePlatform;
  final String _platform;
  final Duration _apnsTokenWait;
  final DocumentReference<Map<String, dynamic>> _tokenRef;
  StreamSubscription<String>? _tokenSubscription;
  Future<void>? _startFuture;
  // The run in progress, if any, and whether this device's registration was
  // last written successfully. A finished run that did not register (the
  // server refused it, no token, offline) may be retried.
  Object? _run;
  bool _registered = false;
  String? _lastToken;
  bool _stopped = false;
  int _generation = 0;
  Future<void> _registrationWork = Future.value();
  Future<void> _deletionWork = Future.value();

  /// Turns notifications on from an explicit user action (the settings
  /// switch), asking the system for permission if it still allows a prompt.
  /// Tapping it again after an attempt that did not register tries again.
  Future<void> start() {
    if (_startFuture != null && _run == null && !_registered) {
      final subscription = _tokenSubscription;
      _tokenSubscription = null;
      unawaited(subscription?.cancel());
      _startFuture = null;
    }
    return _startFuture ??= _tracked(explicit: true);
  }

  Future<void> _tracked({required bool explicit}) async {
    final run = Object();
    _run = run;
    try {
      await _start(explicit: explicit);
    } finally {
      if (identical(_run, run)) _run = null;
    }
  }

  /// Called once per signed-in launch. The first time, it shows the system
  /// prompt; afterwards it re-registers silently only if notifications are
  /// allowed and the user has not turned them off in Fireplace.
  Future<void> startAtLaunch() async {
    if (_startFuture != null) return _startFuture!;
    final gen = _generation;
    final optedOut = await _prefs.read(_optOutKey) != null;
    final asked = await _prefs.read(_askedKey) != null;
    if (optedOut || _stopped || gen != _generation) return;
    final permission = await _messaging.permissionStatus();
    if (_stopped || gen != _generation) return;
    // iOS reports "not determined" until it has asked. Android reports
    // "denied" before the first request, so remember having asked ourselves.
    if (permission == PushPermission.notDetermined || !asked) {
      await _prefs.write(_askedKey, '1');
      if (_stopped || gen != _generation) return;
      return _startFuture ??= _tracked(explicit: false);
    }
    if (permission == PushPermission.allowed) {
      return _startFuture ??= _tracked(explicit: false);
    }
    // Switched off in system settings: drop the token so nothing is sent.
    await _deleteRegistration();
  }

  Future<void> _start({required bool explicit}) async {
    final gen = ++_generation;
    if (_stopped) return;
    if (explicit) await _prefs.delete(_optOutKey);
    if (gen != _generation) return;
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
    _lastToken = token;
    // Finish an old write and its compensating delete before a new generation
    // writes its token. Otherwise old cleanup could erase the restarted record.
    _registrationWork = _registrationWork.then((_) async {
      await _deletionWork;
      if (gen != _generation) return;
      try {
        final showName = await showsName();
        final sound = await playsSound();
        if (gen != _generation) return;
        await _tokenRef.set({
          'token': token,
          'platform': _platform,
          'showName': showName,
          'sound': sound,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        // A write already sent cannot be cancelled; remove its stale result.
        if (gen != _generation) {
          await _deleteRegistration();
        } else {
          _registered = true;
        }
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

  /// What the settings screen shows. Never prompts.
  Future<PushStatus> status() async {
    if (_stopped) return PushStatus.off;
    final permission = await _messaging.permissionStatus();
    if (permission == PushPermission.denied) return PushStatus.blockedBySystem;
    if (permission != PushPermission.allowed) return PushStatus.off;
    if (await _prefs.read(_optOutKey) != null) return PushStatus.off;
    return (await _tokenRef.get()).exists ? PushStatus.on : PushStatus.off;
  }

  /// Whether alerts on this device show the sender's username (default) or
  /// just "Fireplace".
  Future<bool> showsName() async => await _prefs.read(_hideNameKey) == null;

  Future<void> setShowName(bool value) => _setFlag(_hideNameKey, off: !value);

  /// Whether alerts on this device play the Fireplace pop (default) or no
  /// sound. The sender chooses the sound when it sends, so it must know.
  Future<bool> playsSound() async => await _prefs.read(_silentKey) == null;

  Future<void> setSound(bool value) => _setFlag(_silentKey, off: !value);

  Future<void> _setFlag(String key, {required bool off}) async {
    if (off) {
      await _prefs.write(key, '1');
    } else {
      await _prefs.delete(key);
    }
    // Rewrite the registration so the sender sees the new choice.
    final token = _lastToken;
    if (token != null && _startFuture != null && !_stopped) {
      await _saveWhenReady(token, _generation);
    }
  }

  /// Turns notifications off for this device, remembered across launches,
  /// but keeps the service reusable.
  Future<void> disable() async {
    final gen = ++_generation;
    final subscription = _tokenSubscription;
    _tokenSubscription = null;
    _startFuture = null;
    _lastToken = null;
    await subscription?.cancel();
    try {
      await _prefs.write(_optOutKey, '1');
    } catch (_) {
      // Still remove the registration below.
    }
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
    _lastToken = null;
    await subscription?.cancel();
    await _deleteRegistration();
  }

  Future<void> _deleteRegistration() {
    _registered = false;
    return _deletionWork = _deletionWork.then((_) async {
      try {
        await _tokenRef.delete();
      } catch (_) {
        // Cleanup is best-effort. The account/session transition must continue.
      }
    });
  }
}
