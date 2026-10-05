import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/ui/account_deletion_screens.dart';
import 'package:fireplace/src/ui/app.dart';
import 'package:fireplace/src/ui/settings_screen.dart';
import 'package:fireplace/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> settle(WidgetTester t, {int rounds = 20}) async {
  for (var i = 0; i < rounds; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await t.pump();
  }
}

Future<AppSession> makeSession(FakeFirebaseFirestore db, String uid) async {
  final secrets = MemorySecretStore();
  final keys = KeyService(db, secrets);
  final device = await keys.ensureDevice(uid);
  final safety = SafetyService(db, secrets, uid);
  return AppSession(
    uid: uid,
    username: uid,
    device: device,
    chat: ChatService(
      db: db,
      uid: uid,
      device: device,
      keys: keys,
      prekeys: PreKeyService(db, secrets),
      secrets: secrets,
      messages: MemoryMessageStore(),
    ),
    keys: keys,
    safety: safety,
    chatsSub: const Stream<void>.empty().listen((_) {}),
    dispose: () async {},
  );
}

void main() {
  testWidgets(
    'the delete button needs the right username and a password; wrong password shows an error',
    (t) async {
      final db = FakeFirebaseFirestore();
      late AppSession session;
      await t.runAsync(() async {
        await db.collection('users').doc('alice').set({'username': 'alice'});
        session = await makeSession(db, 'alice');
      });
      final calls = <String>[];
      final service = AccountService(
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
            uid: 'alice',
            email: 'alice@users.fireplace.invalid',
          ),
        ),
        db: db,
        secrets: MemorySecretStore(),
        reauthenticate: (_, pw) async {
          calls.add(pw);
          throw FirebaseAuthException(code: 'wrong-password');
        },
      );
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            appSessionProvider.overrideWithValue(AsyncData(session)),
            accountServiceProvider.overrideWithValue(service),
          ],
          child: MaterialApp(
            theme: fireplaceTheme(Brightness.light),
            home: const DeleteAccountScreen(),
          ),
        ),
      );
      await settle(t, rounds: 3);
      FilledButton button() =>
          t.widget<FilledButton>(find.byKey(const Key('deleteAccount')));
      await t.scrollUntilVisible(
        find.byKey(const Key('deleteAccount')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(button().onPressed, isNull);

      await t.enterText(
        find.byKey(const Key('confirmPassword')),
        'hunter2hunter2',
      );
      await t.pump();
      expect(button().onPressed, isNull); // username not typed yet
      await t.enterText(
        find.byKey(const Key('confirmUsername')),
        'someone else',
      );
      await t.pump();
      expect(button().onPressed, isNull);
      await t.enterText(find.byKey(const Key('confirmUsername')), ' Alice ');
      await t.pump();
      expect(button().onPressed, isNotNull);

      await t.tap(find.byKey(const Key('deleteAccount')));
      await settle(t);
      expect(calls, ['hunter2hunter2']);
      expect(find.byKey(const Key('deleteError')), findsOneWidget);
      expect(find.text('That password is not correct.'), findsOneWidget);
      // nothing was deleted
      expect(
        (await t.runAsync(() => db.collection('users').doc('alice').get()))!
            .exists,
        isTrue,
      );
    },
  );

  testWidgets('settings offers account deletion and explains what is deleted', (
    t,
  ) async {
    final db = FakeFirebaseFirestore();
    late AppSession session;
    await t.runAsync(() async => session = await makeSession(db, 'alice'));
    await t.pumpWidget(
      ProviderScope(
        overrides: [appSessionProvider.overrideWithValue(AsyncData(session))],
        child: MaterialApp(
          theme: fireplaceTheme(Brightness.light),
          home: const SettingsScreen(),
        ),
      ),
    );
    await settle(t, rounds: 3);
    await t.scrollUntilVisible(find.byKey(const Key('deleteAccountTile')), 200);
    await t.ensureVisible(find.byKey(const Key('deleteAccountTile')));
    await t.pump();
    await t.tap(find.byKey(const Key('deleteAccountTile')));
    await t.pumpAndSettle();
    expect(find.byType(DeleteAccountScreen), findsOneWidget);
    expect(find.text('Delete account'), findsWidgets);
    expect(find.text('What gets deleted'), findsOneWidget);
    expect(find.text('What stays'), findsOneWidget);
  });

  testWidgets('a half-deleted account is sent to the finish-deleting screen', (
    t,
  ) async {
    final user = MockUser(uid: 'alice', email: 'alice@users.fireplace.invalid');
    await t.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          authUserProvider.overrideWith((_) => Stream<User?>.value(user)),
          appSessionProvider.overrideWith(
            (_) => throw AccountDeletionPending('alice'),
          ),
        ],
        child: const FireplaceApp(),
      ),
    );
    await settle(t, rounds: 5);
    expect(find.text('Finish deleting'), findsOneWidget);
    await t.scrollUntilVisible(
      find.byKey(const Key('confirmPassword')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('confirmUsername')), findsNothing);
    expect(find.byKey(const Key('confirmPassword')), findsOneWidget);
  });
}
