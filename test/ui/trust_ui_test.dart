import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fireplace/fireplace_crypto.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/ui/devices_screen.dart';
import 'package:fireplace/src/ui/theme.dart';
import 'package:fireplace/src/ui/verify_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

Future<AppSession> makeSession(FakeFirebaseFirestore db, String uid) async {
  final secrets = MemorySecretStore();
  final keys = KeyService(db, secrets);
  final device = await keys.ensureDevice(uid);
  final chat = ChatService(
    db: db,
    uid: uid,
    device: device,
    keys: keys,
    safety: SafetyService(db, secrets, 'alice'),
    prekeys: PreKeyService(db, secrets),
    secrets: secrets,
    messages: MemoryMessageStore(),
  );
  return AppSession(
    uid: uid,
    username: uid,
    device: device,
    chat: chat,
    keys: keys,
    safety: SafetyService(db, secrets, uid),
    chatsSub: const Stream<void>.empty().listen((_) {}),
    dispose: () async {},
  );
}

Widget host(AppSession s, Widget child) => ProviderScope(
  overrides: [
    authUserProvider.overrideWithValue(const AsyncData(null)),
    appSessionProvider.overrideWithValue(AsyncData(s)),
  ],
  child: MaterialApp(theme: fireplaceTheme(Brightness.light), home: child),
);

void main() {
  testWidgets('VerifyScreen shows 60-digit number + QR and toggles verified', (
    t,
  ) async {
    await t.runAsync(() async {});
    final db = FakeFirebaseFirestore();
    late AppSession alice;
    await t.runAsync(() async {
      alice = await makeSession(db, 'alice');
      await makeSession(db, 'bob');
    });
    await t.pumpWidget(
      host(alice, const VerifyScreen(peerUid: 'bob', peerName: 'bob')),
    );
    for (var i = 0; i < 40; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await t.pump();
      if (find.byType(QrImageView).evaluate().isNotEmpty) break;
    }
    expect(find.byType(QrImageView), findsOneWidget);
    final groups = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('safetyGroup_'),
    );
    expect(groups, findsNWidgets(12));
    expect(find.text('Not verified yet'), findsOneWidget);

    await t.scrollUntilVisible(find.byKey(const Key('toggleVerified')), 200);
    await t.tap(find.byKey(const Key('toggleVerified')));
    for (var i = 0; i < 20; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await t.pump();
    }
    await t.drag(find.byType(ListView), const Offset(0, 800));
    await t.pump();
    expect(find.text('Verified'), findsOneWidget);
    expect(await t.runAsync(() => alice.keys.isVerified('bob')), isTrue);
  });

  testWidgets('DevicesScreen lists devices and revokes another one', (t) async {
    final db = FakeFirebaseFirestore();
    late AppSession a1;
    late String otherId;
    await t.runAsync(() async {
      a1 = await makeSession(db, 'alice');
      // second device of the same account
      final id = a1.device.identity;
      final dk = await DeviceKeys.generate();
      final b = await dk.certify(id, 'alice');
      otherId = dk.deviceId;
      await db.collection('users/alice/devices').doc(dk.deviceId).set({
        ...b.toFirestore(),
        'createdAt': Timestamp.now(),
      });
    });
    await t.pumpWidget(host(a1, const DevicesScreen()));
    for (var i = 0; i < 40; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await t.pump();
      if (find.text('This device').evaluate().isNotEmpty) break;
    }
    expect(find.text('This device'), findsOneWidget);
    await t.tap(find.byKey(Key('revoke_$otherId')));
    // The guarded device action remains busy while confirmation is open.
    await t.pump(const Duration(milliseconds: 350));
    await t.tap(find.byKey(const Key('confirmRevoke')));
    for (var i = 0; i < 40; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await t.pump();
      if (find.text('Removed').evaluate().isNotEmpty) break;
    }
    expect(find.text('Removed'), findsOneWidget);
  });
}
