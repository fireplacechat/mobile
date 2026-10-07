import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/src/model/push/push_notification_service.dart';

class _FakeMessaging implements PushMessagingClient {
  bool permission = true;
  String? apnsToken = 'apns-token';
  String? token = 'fcm-token-0123456789abcdef';
  int getTokenCalls = 0;
  int presentationCalls = 0;
  final refresh = StreamController<String>.broadcast();

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<bool> requestPermission() async => permission;

  @override
  Future<String?> getApnsToken() async => apnsToken;

  @override
  Future<String?> getToken() async {
    getTokenCalls++;
    return token;
  }

  @override
  Stream<String> get onTokenRefresh => refresh.stream;

  @override
  Future<void> setForegroundPresentation() async {
    presentationCalls++;
  }
}

void main() {
  _raceTests();
  group('PushNotificationService', () {
    test('stores only the current device token and refreshes it', () async {
      final db = FakeFirebaseFirestore();
      final messaging = _FakeMessaging();
      final service = PushNotificationService(
        db: db,
        uid: 'alice',
        deviceId: 'alice-device-1',
        messaging: messaging,
        platform: 'ios',
        isApplePlatform: true,
      );

      await service.start();
      var doc = await db.doc('users/alice/pushTokens/alice-device-1').get();
      expect(doc.data()?['token'], 'fcm-token-0123456789abcdef');
      expect(doc.data()?['platform'], 'ios');
      expect(doc.data()?['updatedAt'], isNotNull);
      expect(messaging.presentationCalls, 1);

      messaging.refresh.add('fcm-token-abcdef0123456789');
      await Future<void>.delayed(Duration.zero);
      doc = await db.doc('users/alice/pushTokens/alice-device-1').get();
      expect(doc.data()?['token'], 'fcm-token-abcdef0123456789');

      await service.unregister();
      expect(
        (await db.doc('users/alice/pushTokens/alice-device-1').get()).exists,
        isFalse,
      );
      await messaging.refresh.close();
    });

    test(
      'does not request an FCM token without notification permission',
      () async {
        final db = FakeFirebaseFirestore();
        final messaging = _FakeMessaging()..permission = false;
        final service = PushNotificationService(
          db: db,
          uid: 'alice',
          deviceId: 'alice-device-1',
          messaging: messaging,
          isApplePlatform: false,
        );

        await service.start();
        expect(messaging.getTokenCalls, 0);
        expect(
          (await db.doc('users/alice/pushTokens/alice-device-1').get()).exists,
          isFalse,
        );
        await service.unregister();
        await messaging.refresh.close();
      },
    );

    test('waits for APNs registration before fetching the FCM token', () async {
      final db = FakeFirebaseFirestore();
      final messaging = _FakeMessaging()..apnsToken = null;
      final service = PushNotificationService(
        db: db,
        uid: 'alice',
        deviceId: 'alice-device-1',
        messaging: messaging,
        isApplePlatform: true,
        apnsTokenWait: Duration.zero,
      );

      await service.start();
      expect(messaging.getTokenCalls, 1);
      expect(
        (await db.doc('users/alice/pushTokens/alice-device-1').get()).exists,
        isFalse,
      );
      await service.unregister();
      await messaging.refresh.close();
    });

    test(
      'startIfPermitted never prompts and does nothing without prior consent',
      () async {
        final db = FakeFirebaseFirestore();
        final messaging = _FakeMessaging()..permission = false;
        final service = PushNotificationService(
          db: db,
          uid: 'alice',
          deviceId: 'alice-device-1',
          messaging: messaging,
          platform: 'android',
          isApplePlatform: false,
        );
        await service.startIfPermitted();
        expect(messaging.getTokenCalls, 0);
        expect(messaging.presentationCalls, 0);
        expect(
          (await db.doc('users/alice/pushTokens/alice-device-1').get()).exists,
          isFalse,
        );
        messaging.permission = true; // the user turned it on in Settings
        await service.startIfPermitted();
        expect(
          (await db.doc('users/alice/pushTokens/alice-device-1').get()).exists,
          isTrue,
        );
      },
    );
  });
}

class _ControlledMessaging extends _FakeMessaging {
  Future<String?> Function()? tokenRead;
  Future<String?> Function()? apnsRead;
  Future<bool> Function()? permissionRead;
  Future<bool> Function()? priorPermissionRead;
  Future<void> Function()? presentation;
  int activeSubscriptions = 0;

  @override
  Future<bool> hasPermission() =>
      priorPermissionRead?.call() ?? super.hasPermission();

  @override
  Future<void> setForegroundPresentation() =>
      presentation?.call() ?? super.setForegroundPresentation();

  @override
  Future<String?> getToken() {
    if (tokenRead == null) return super.getToken();
    getTokenCalls++;
    return tokenRead!();
  }

  @override
  Future<String?> getApnsToken() => apnsRead?.call() ?? super.getApnsToken();

  @override
  Future<bool> requestPermission() =>
      permissionRead?.call() ?? super.requestPermission();

  @override
  Stream<String> get onTokenRefresh => Stream<String>.multi((controller) {
    activeSubscriptions++;
    final sub = refresh.stream.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    controller.onCancel = () async {
      activeSubscriptions--;
      await sub.cancel();
    };
  }, isBroadcast: true);
}

class _WriteGateFirestore extends Fake implements FirebaseFirestore {
  final delegate = FakeFirebaseFirestore();
  Future<void> Function()? beforeSet;
  Future<void> Function()? beforeDelete;
  int writes = 0;

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _WriteGateCollection(delegate.collection(path), this);
}

// Firestore test wrapper delegates all operations except the controlled write.
// ignore: subtype_of_sealed_class
class _WriteGateCollection extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  _WriteGateCollection(this.delegate, this.gate);
  final CollectionReference<Map<String, dynamic>> delegate;
  final _WriteGateFirestore gate;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _WriteGateDocument(delegate.doc(path), gate);
}

// Firestore test wrapper delegates all operations except controlled completion.
// ignore: subtype_of_sealed_class
class _WriteGateDocument extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  _WriteGateDocument(this.delegate, this.gate);
  final DocumentReference<Map<String, dynamic>> delegate;
  final _WriteGateFirestore gate;

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _WriteGateCollection(delegate.collection(path), gate);

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    gate.writes++;
    await gate.beforeSet?.call();
    await delegate.set(data, options);
  }

  @override
  Future<void> delete() async {
    await gate.beforeDelete?.call();
    await delegate.delete();
  }

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([GetOptions? options]) =>
      delegate.get(options);
}

class _RaceHarness {
  _RaceHarness({bool apple = false}) {
    service = PushNotificationService(
      db: db,
      uid: 'fred',
      deviceId: 'fred-device',
      messaging: messaging,
      isApplePlatform: apple,
    );
    addTearDown(() async {
      await service.unregister();
      await messaging.refresh.close();
    });
  }
  final db = _WriteGateFirestore();
  final messaging = _ControlledMessaging();
  late final PushNotificationService service;
  Future<bool> registered() async =>
      (await db.delegate.doc('users/fred/pushTokens/fred-device').get()).exists;
}

Future<void> _flushPushWork() => Future<void>.delayed(Duration.zero);

void _raceTests() {
  group('push lifecycle races', () {
    test(
      'disable during silent permission lookup prevents late start',
      () async {
        final h = _RaceHarness();
        final entered = Completer<void>();
        final permission = Completer<bool>();
        h.messaging.priorPermissionRead = () {
          entered.complete();
          return permission.future;
        };
        final starting = h.service.startIfPermitted();
        await entered.future;
        await h.service.disable();
        permission.complete(true);
        await starting;
        expect(await h.registered(), isFalse);
        expect(h.messaging.activeSubscriptions, 0);
      },
    );

    test('disable during foreground setup prevents late start', () async {
      final h = _RaceHarness();
      final entered = Completer<void>();
      final ready = Completer<void>();
      h.messaging.presentation = () {
        entered.complete();
        return ready.future;
      };
      final starting = h.service.start();
      await entered.future;
      await h.service.disable();
      ready.complete();
      await starting;
      expect(await h.registered(), isFalse);
      expect(h.messaging.activeSubscriptions, 0);
    });

    test('quick starts share the same run', () async {
      final h = _RaceHarness();
      final token = Completer<String?>();
      h.messaging.tokenRead = () => token.future;
      final first = h.service.start();
      expect(h.service.start(), same(first));
      token.complete('token');
      await first;
      expect(h.messaging.getTokenCalls, 1);
      expect(h.messaging.activeSubscriptions, 1);
    });

    test('restart waits for every earlier deletion', () async {
      final h = _RaceHarness();
      final entered = Completer<void>();
      final release = Completer<void>();
      var deletes = 0;
      h.db.beforeDelete = () {
        if (deletes++ == 0) {
          entered.complete();
          return release.future;
        }
        return Future.value();
      };
      h.messaging.permission = false;
      final oldStart = h.service.start();
      await entered.future;
      final disabling = h.service.disable();
      await _flushPushWork();
      h.messaging.permission = true;
      final newStart = h.service.start();
      await _flushPushWork();
      release.complete();
      await Future.wait([oldStart, disabling, newStart]);
      expect(await h.registered(), isTrue);
      expect(h.messaging.activeSubscriptions, 1);
    });

    test('stale write cleanup preserves the restarted registration', () async {
      final h = _RaceHarness();
      final entered = Completer<void>();
      final release = Completer<void>();
      h.db.beforeSet = () {
        if (h.db.writes == 1) {
          entered.complete();
          return release.future;
        }
        return Future.value();
      };
      final oldStart = h.service.start();
      await entered.future;
      await h.service.disable();
      h.messaging.token = 'new-token';
      final newStart = h.service.start();
      await _flushPushWork();
      release.complete();
      await Future.wait([oldStart, newStart]);
      expect(await h.registered(), isTrue);
      expect(
        (await h.db.delegate.doc('users/fred/pushTokens/fred-device').get())
            .data()?['token'],
        'new-token',
      );
      expect(h.messaging.activeSubscriptions, 1);
    });

    test('disable during getToken prevents registration and refresh', () async {
      final h = _RaceHarness();
      final entered = Completer<void>();
      final token = Completer<String?>();
      h.messaging.tokenRead = () {
        entered.complete();
        return token.future;
      };
      final starting = h.service.start();
      await entered.future;
      await h.service.disable();
      token.complete('old-token');
      await starting;
      expect(await h.registered(), isFalse);
      expect(h.messaging.activeSubscriptions, 0);
      h.messaging.refresh.add('late-refresh');
      await _flushPushWork();
      expect(await h.registered(), isFalse);
    });

    test('disable during APNs wait prevents registration', () async {
      final h = _RaceHarness(apple: true);
      final entered = Completer<void>();
      final apns = Completer<String?>();
      h.messaging.apnsRead = () {
        entered.complete();
        return apns.future;
      };
      final starting = h.service.start();
      await entered.future;
      await h.service.disable();
      apns.complete('apns-token');
      await starting;
      expect(await h.registered(), isFalse);
    });

    test('disable during refresh APNs wait prevents registration', () async {
      final h = _RaceHarness(apple: true);
      await h.service.start();
      final entered = Completer<void>();
      final apns = Completer<String?>();
      h.messaging.apnsRead = () {
        entered.complete();
        return apns.future;
      };
      h.messaging.refresh.add('refreshed-token');
      await entered.future;
      await h.service.disable();
      apns.complete('apns-token');
      await _flushPushWork();
      expect(await h.registered(), isFalse);
    });

    test('unregister during start prevents a leaked subscription', () async {
      final h = _RaceHarness();
      final entered = Completer<void>();
      final permission = Completer<bool>();
      h.messaging.permissionRead = () {
        entered.complete();
        return permission.future;
      };
      final starting = h.service.start();
      await entered.future;
      await h.service.unregister();
      permission.complete(true);
      await starting;
      expect(await h.registered(), isFalse);
      expect(h.messaging.activeSubscriptions, 0);
      h.messaging.refresh.add('late-refresh');
      await _flushPushWork();
      expect(await h.registered(), isFalse);
    });

    test(
      'restart after disable leaves exactly one refresh subscription',
      () async {
        final h = _RaceHarness();
        final entered = Completer<void>();
        final permission = Completer<bool>();
        var calls = 0;
        h.messaging.permissionRead = () {
          if (calls++ == 0) {
            entered.complete();
            return permission.future;
          }
          return Future.value(true);
        };
        final oldStart = h.service.start();
        await entered.future;
        await h.service.disable();
        await h.service.start();
        permission.complete(true);
        await oldStart;
        expect(await h.registered(), isTrue);
        expect(h.messaging.activeSubscriptions, 1);
        for (final token in ['first-refresh', 'second-refresh']) {
          final before = h.db.writes;
          h.messaging.refresh.add(token);
          await _flushPushWork();
          expect(h.db.writes, before + 1);
        }
      },
    );

    test('disable compensates for a token write already in flight', () async {
      final h = _RaceHarness(apple: true);
      final entered = Completer<void>();
      final release = Completer<void>();
      h.db.beforeSet = () {
        entered.complete();
        return release.future;
      };
      final starting = h.service.start();
      await entered.future;
      await h.service.disable();
      release.complete();
      await starting;
      expect(h.db.writes, 1);
      expect(await h.registered(), isFalse);
    });
  });
}
