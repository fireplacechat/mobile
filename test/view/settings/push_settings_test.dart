import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fireplace/src/model/notifications/system_notifications.dart';
import 'package:fireplace/src/model/push/push_notification_service.dart';
import 'package:fireplace/src/view/settings/push_settings.dart';

class _Messaging implements PushMessagingClient {
  PushPermission permission = PushPermission.allowed;
  String? token = 'fcm-token-0123456789abcdef';
  final refresh = StreamController<String>.broadcast();
  @override
  Future<PushPermission> permissionStatus() async => permission;
  @override
  Future<bool> requestPermission() async =>
      permission == PushPermission.allowed;
  @override
  Future<String?> getApnsToken() async => 'apns';
  @override
  Future<String?> getToken() async => token;
  @override
  Stream<String> get onTokenRefresh => refresh.stream;
  @override
  Future<void> setForegroundPresentation() async {}
}

class _System implements SystemNotifications {
  int opened = 0;
  @override
  Future<void> setBadge(int count) async {}
  @override
  Future<void> clearDelivered() async {}
  @override
  Future<void> openSettings() async => opened++;
  @override
  Future<void> playSendSound() async {}
}

// The service's Firestore and preference calls finish outside the fake clock.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  late FakeFirebaseFirestore db;
  late _Messaging messaging;
  late _System system;
  late PushNotificationService service;

  setUp(() {
    db = FakeFirebaseFirestore();
    messaging = _Messaging();
    system = _System();
    service = PushNotificationService(
      db: db,
      uid: 'alice',
      deviceId: 'alice-device-1',
      messaging: messaging,
      isApplePlatform: false,
      platform: 'ios',
    );
    addTearDown(messaging.refresh.close);
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          systemNotificationsProvider.overrideWithValue(system),
          appleWordingProvider.overrideWithValue(true),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ListView(children: [PushSettingsSection(service: service)]),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  bool switchValue(WidgetTester tester, String key) =>
      tester.widget<SwitchListTile>(find.byKey(Key(key))).value;
  bool enabled(WidgetTester tester, String key) =>
      tester.widget<SwitchListTile>(find.byKey(Key(key))).onChanged != null;

  testWidgets('turning notifications on and off', (tester) async {
    await pump(tester);
    expect(find.text('Allow notifications'), findsOneWidget);
    expect(switchValue(tester, 'pushSwitch'), isFalse);
    expect(enabled(tester, 'pushShowName'), isFalse);

    await tester.tap(find.byKey(const Key('pushSwitch')));
    await settle(tester);
    expect(switchValue(tester, 'pushSwitch'), isTrue);
    expect(find.text('Off in iOS Settings'), findsNothing);
    expect(enabled(tester, 'pushShowName'), isTrue);

    await tester.tap(find.byKey(const Key('pushShowName')));
    await settle(tester);
    expect(switchValue(tester, 'pushShowName'), isFalse);
    expect(
      (await db.doc('users/alice/pushTokens/alice-device-1').get())
          .data()?['showName'],
      isFalse,
    );

    await tester.tap(find.byKey(const Key('pushSwitch')));
    await settle(tester);
    expect(switchValue(tester, 'pushSwitch'), isFalse);
    expect(enabled(tester, 'pushShowName'), isFalse);
  });

  testWidgets('the notification sound switch follows the registration', (
    tester,
  ) async {
    await pump(tester);
    expect(enabled(tester, 'pushSound'), isFalse, reason: 'off until allowed');
    await tester.tap(find.byKey(const Key('pushSwitch')));
    await settle(tester);
    expect(switchValue(tester, 'pushSound'), isTrue, reason: 'on by default');
    await tester.tap(find.byKey(const Key('pushSound')));
    await settle(tester);
    expect(switchValue(tester, 'pushSound'), isFalse);
    expect(
      (await db.doc('users/alice/pushTokens/alice-device-1').get())
          .data()?['sound'],
      isFalse,
    );
  });

  testWidgets('a failed turn-on says so, and the next tap retries', (
    tester,
  ) async {
    messaging.token = null; // registration cannot happen
    await pump(tester);
    await tester.tap(find.byKey(const Key('pushSwitch')));
    await settle(tester);
    expect(switchValue(tester, 'pushSwitch'), isFalse);
    expect(find.text('Could not change. Try again.'), findsOneWidget);

    messaging.token = 'fcm-token-0123456789abcdef';
    await tester.tap(find.byKey(const Key('pushSwitch')));
    await settle(tester);
    expect(switchValue(tester, 'pushSwitch'), isTrue);
    expect(find.text('Could not change. Try again.'), findsNothing);
  });

  testWidgets('blocked in system settings opens them', (tester) async {
    messaging.permission = PushPermission.denied;
    await pump(tester);
    expect(find.text('Off in iOS Settings'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pushSwitch')));
    await settle(tester);
    expect(system.opened, 1);
    expect(switchValue(tester, 'pushSwitch'), isFalse);
  });

  testWidgets('returning to the app rereads the permission', (tester) async {
    messaging.permission = PushPermission.denied;
    await pump(tester);
    messaging.permission = PushPermission.allowed;
    await tester.runAsync(service.start);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(switchValue(tester, 'pushSwitch'), isTrue);
  });

  testWidgets('sounds, banners and badges open the system settings', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('pushSystemSettings')));
    await settle(tester);
    expect(system.opened, 1);
  });
}
