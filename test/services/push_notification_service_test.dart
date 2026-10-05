import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/src/services/push_notification_service.dart';

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
