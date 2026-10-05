import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/ui/new_device_screen.dart';
import 'package:fireplace/src/ui/recovery_screens.dart';
import 'package:fireplace/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> settle(WidgetTester t, {int rounds = 30}) async {
  for (var i = 0; i < rounds; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await t.pump();
  }
}

void main() {
  testWidgets(
    'RecoveryKeyScreen: create key, must confirm saving, backup stored',
    (t) async {
      // The redesigned page is taller than the default test window; show it all.
      t.view.physicalSize = const Size(800, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final db = FakeFirebaseFirestore();
      final secrets = MemorySecretStore();
      final keys = KeyService(db, secrets);
      final recovery = RecoveryService(db, secrets, keys);
      late AppSession session;
      await t.runAsync(() async {
        final device = await keys.ensureDevice('alice');
        session = AppSession(
          uid: 'alice',
          username: 'alice',
          device: device,
          chat: ChatService(
            db: db,
            uid: 'alice',
            device: device,
            keys: keys,
            safety: SafetyService(db, secrets, 'alice'),
            prekeys: PreKeyService(db, secrets),
            secrets: secrets,
            messages: MemoryMessageStore(),
          ),
          keys: keys,
          safety: SafetyService(db, secrets, 'alice'),
          chatsSub: const Stream<void>.empty().listen((_) {}),
          dispose: () async {},
        );
      });
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            appSessionProvider.overrideWithValue(AsyncData(session)),
            recoveryServiceProvider.overrideWithValue(recovery),
          ],
          child: MaterialApp(
            theme: fireplaceTheme(Brightness.light),
            home: const RecoveryKeyScreen(),
          ),
        ),
      );
      await settle(t, rounds: 5);
      expect(find.text('No recovery key yet'), findsOneWidget);
      await t.tap(find.byKey(const Key('createRecovery')));
      await settle(t);
      final shown = (t.widget(
        find.byKey(const Key('recoveryKeyText')),
      ) as SelectableText).data!;
      expect(RegExp(r'^([A-Z2-7]{4}-){8}[A-Z2-7]{4}$').hasMatch(shown), isTrue);
      // Done is disabled until the box is ticked
      expect(
        t.widget<FilledButton>(find.byKey(const Key('recoveryDone'))).onPressed,
        isNull,
      );
      await t.tap(find.byKey(const Key('savedCheck')));
      await t.pump();
      expect(
        t.widget<FilledButton>(find.byKey(const Key('recoveryDone'))).onPressed,
        isNotNull,
      );
      // the stored backup is decryptable with exactly the displayed key
      final fresh = RecoveryService(
        db,
        MemorySecretStore(),
        KeyService(db, MemorySecretStore()),
      );
      final restored = await t.runAsync(
        () => fresh.restoreWithRecoveryKey('alice', shown),
      );
      expect(
        restored!.identity.publicBytes,
        session.device.identity.publicBytes,
      );
    },
  );

  testWidgets(
    'NewDeviceScreen: recovery key entry shows errors, then installs the device',
    (t) async {
      final db = FakeFirebaseFirestore();
      late String goodKey;
      await t.runAsync(() async {
        final s = MemorySecretStore();
        final k = KeyService(db, s);
        final dev = await k.ensureDevice('alice');
        goodKey = await (await RecoveryService(
          db,
          s,
          k,
        ).createBackup('alice', dev.identity)).display();
      });
      final secrets = MemorySecretStore();
      final recovery = RecoveryService(db, secrets, KeyService(db, secrets));
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            appSessionProvider.overrideWithValue(const AsyncData(null)),
            recoveryServiceProvider.overrideWithValue(recovery),
          ],
          child: MaterialApp(
            theme: fireplaceTheme(Brightness.light),
            home: const NewDeviceScreen(uid: 'alice'),
          ),
        ),
      );
      expect(find.byKey(const Key('optLink')), findsOneWidget);
      expect(find.byKey(const Key('optRecovery')), findsOneWidget);
      expect(find.byKey(const Key('optReset')), findsOneWidget);

      await t.tap(find.byKey(const Key('optRecovery')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('recoveryInput')), 'NOPE');
      await t.tap(find.byKey(const Key('recoverGo')));
      await settle(t, rounds: 10);
      expect(find.byKey(const Key('recoveryError')), findsOneWidget);
      expect(await secrets.read('identity:alice'), isNull);

      await t.enterText(find.byKey(const Key('recoveryInput')), goodKey);
      await t.tap(find.byKey(const Key('recoverGo')));
      await settle(t);
      expect(await secrets.read('identity:alice'), isNotNull);
    },
  );
}
