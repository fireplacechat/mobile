import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/src/db/secret_store.dart';
import 'package:fireplace/src/model/push/push_notification_service.dart';

class _FakeMessaging implements PushMessagingClient {
  bool permission = true;
  bool undetermined = false;
  int requestCalls = 0;
  String? apnsToken = 'apns-token';
  String? token = 'fcm-token-0123456789abcdef';
  int getTokenCalls = 0;
  int presentationCalls = 0;
  final refresh = StreamController<String>.broadcast();

  @override
  Future<PushPermission> permissionStatus() async => undetermined
      ? PushPermission.notDetermined
      : permission
      ? PushPermission.allowed
      : PushPermission.denied;

  @override
  Future<bool> requestPermission() async {
    requestCalls++;
    undetermined = false;
    return permission;
  }

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

    group('launch, opt-out and name preference', () {
      late FakeFirebaseFirestore db;
      late _FakeMessaging messaging;
      late MemorySecretStore prefs;
      final doc = 'users/alice/pushTokens/alice-device-1';
      PushNotificationService service() {
        final s = PushNotificationService(
          db: db,
          uid: 'alice',
          deviceId: 'alice-device-1',
          messaging: messaging,
          preferences: prefs,
          platform: 'android',
          isApplePlatform: false,
        );
        addTearDown(s.unregister);
        return s;
      }

      setUp(() {
        db = FakeFirebaseFirestore();
        messaging = _FakeMessaging()..undetermined = true;
        prefs = MemorySecretStore();
        addTearDown(messaging.refresh.close);
      });

      test('the first launch shows the system prompt and registers', () async {
        await service().startAtLaunch();
        expect(messaging.requestCalls, 1);
        expect((await db.doc(doc).get()).data()?['showName'], isTrue);
      });

      test('a declined prompt is never shown again at launch', () async {
        messaging.permission = false;
        await service().startAtLaunch();
        expect(messaging.requestCalls, 1);
        await service().startAtLaunch();
        expect(messaging.requestCalls, 1);
        expect((await db.doc(doc).get()).exists, isFalse);
      });

      test(
        'Android reports denied before asking; the first launch still asks',
        () async {
          messaging
            ..undetermined = false
            ..permission = false;
          await service().startAtLaunch();
          expect(messaging.requestCalls, 1);
        },
      );

      test('later launches re-register silently when allowed', () async {
        await service().startAtLaunch();
        await db.doc(doc).delete();
        await service().startAtLaunch();
        expect((await db.doc(doc).get()).exists, isTrue);
      });

      test('turning off in the app is remembered across launches', () async {
        final first = service();
        await first.startAtLaunch();
        expect(await first.status(), PushStatus.on);
        await first.disable();
        expect(await first.status(), PushStatus.off);
        expect((await db.doc(doc).get()).exists, isFalse);

        final next = service();
        await next.startAtLaunch();
        expect((await db.doc(doc).get()).exists, isFalse);
        expect(await next.status(), PushStatus.off);

        await next.start(); // the user turns it back on
        expect(await next.status(), PushStatus.on);
        await service().startAtLaunch();
        expect((await db.doc(doc).get()).exists, isTrue);
      });

      test('turned off in system settings removes the registration', () async {
        await service().startAtLaunch();
        messaging.permission = false;
        final later = service();
        await later.startAtLaunch();
        expect((await db.doc(doc).get()).exists, isFalse);
        expect(await later.status(), PushStatus.blockedBySystem);
      });

      test('hiding the name rewrites the registration and persists', () async {
        final s = service();
        await s.startAtLaunch();
        expect(await s.showsName(), isTrue);
        await s.setShowName(false);
        expect(await s.showsName(), isFalse);
        expect((await db.doc(doc).get()).data()?['showName'], isFalse);

        await db.doc(doc).delete();
        await service().startAtLaunch();
        expect((await db.doc(doc).get()).data()?['showName'], isFalse);
        await s.setShowName(true);
        expect((await db.doc(doc).get()).data()?['showName'], isTrue);
      });

      test(
        'the notification sound is on by default and can be turned off',
        () async {
          final s = service();
          await s.startAtLaunch();
          expect(await s.playsSound(), isTrue);
          expect((await db.doc(doc).get()).data()?['sound'], isTrue);
          await s.setSound(false);
          expect(await s.playsSound(), isFalse);
          expect((await db.doc(doc).get()).data()?['sound'], isFalse);
          // The name choice is independent.
          expect((await db.doc(doc).get()).data()?['showName'], isTrue);

          await db.doc(doc).delete();
          await service().startAtLaunch();
          expect((await db.doc(doc).get()).data()?['sound'], isFalse);
        },
      );

      test(
        'message previews are on by default, stay on the device and persist',
        () async {
          final s = service();
          await s.startAtLaunch();
          expect(await s.showsPreview(), isTrue);
          final before = (await db.doc(doc).get()).data();
          await s.setShowPreview(false);
          expect(await s.showsPreview(), isFalse);
          // The server is never told: the registration is unchanged.
          expect((await db.doc(doc).get()).data(), before);
          expect(before!.containsKey('preview'), isFalse);
          // Another instance (the next launch) reads the same choice.
          expect(await service().showsPreview(), isFalse);
          await s.setShowPreview(true);
          expect(await service().showsPreview(), isTrue);
        },
      );

      test('Android registrations say they handle data pushes', () async {
        await service().startAtLaunch();
        expect((await db.doc(doc).get()).data()?['dataPush'], isTrue);
        final ios = PushNotificationService(
          db: db,
          uid: 'alice',
          deviceId: 'alice-device-2',
          messaging: messaging,
          preferences: prefs,
          platform: 'ios',
          isApplePlatform: false,
        );
        addTearDown(ios.unregister);
        await ios.startAtLaunch();
        final iosDoc = await db
            .doc('users/alice/pushTokens/alice-device-2')
            .get();
        expect(iosDoc.exists, isTrue);
        expect(iosDoc.data()!.containsKey('dataPush'), isFalse);
      });

      test('the device choices are read together, all on by default', () async {
        var choices = await PushChoices.read(prefs, 'alice');
        expect(
          [choices.alerts, choices.preview, choices.showName, choices.sound],
          [true, true, true, true],
        );
        expect(choices.channel, 'messages');
        final s = service();
        await s.setShowPreview(false);
        await s.setSound(false);
        await s.setShowName(false);
        await s.disable();
        choices = await PushChoices.read(prefs, 'alice');
        expect(
          [choices.alerts, choices.preview, choices.showName, choices.sound],
          [false, false, false, false],
        );
        expect(choices.channel, 'messages_silent');
      });

      test('changing the name preference while off writes nothing', () async {
        final s = service();
        await s.setShowName(false);
        expect((await db.doc(doc).get()).exists, isFalse);
      });
    });
  });
}

class _ControlledMessaging extends _FakeMessaging {
  Future<String?> Function()? tokenRead;
  Future<String?> Function()? apnsRead;
  Future<bool> Function()? permissionRead;
  Future<PushPermission> Function()? priorPermissionRead;
  Future<void> Function()? presentation;
  int activeSubscriptions = 0;

  @override
  Future<PushPermission> permissionStatus() =>
      priorPermissionRead?.call() ?? super.permissionStatus();

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
        final permission = Completer<PushPermission>();
        h.messaging.priorPermissionRead = () {
          entered.complete();
          return permission.future;
        };
        final starting = h.service.startAtLaunch();
        await entered.future;
        await h.service.disable();
        permission.complete(PushPermission.allowed);
        await starting;
        expect(await h.registered(), isFalse);
        expect(h.messaging.activeSubscriptions, 0);
      },
    );

    test(
      'a refused registration is retried on the next tap, not reused',
      () async {
        // What production does while its rules predate `showName`/`sound`.
        final h = _RaceHarness();
        var refuse = true;
        h.db.beforeSet = () async {
          if (refuse) throw StateError('permission-denied');
        };
        await h.service.start();
        expect(await h.registered(), isFalse);
        expect(await h.service.status(), PushStatus.off);

        refuse = false; // the new rules are deployed
        await h.service.start();
        expect(await h.registered(), isTrue);
        expect(await h.service.status(), PushStatus.on);
        expect(h.messaging.activeSubscriptions, 1);
      },
    );

    test('a registered start is shared, not repeated', () async {
      final h = _RaceHarness();
      await h.service.start();
      final writes = h.db.writes;
      await h.service.start();
      expect(h.db.writes, writes);
      expect(h.messaging.activeSubscriptions, 1);
    });

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
