// Two real sessions over one fake Firestore, for Requests and safety screens.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> settle(WidgetTester t, {int rounds = 25}) async {
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
  final prekeys = PreKeyService(db, secrets);
  await prekeys.maintain(uid, device);
  final safety = SafetyService(db, secrets, uid);
  await safety.start();
  final chat = ChatService(
    db: db,
    uid: uid,
    device: device,
    keys: keys,
    prekeys: prekeys,
    secrets: secrets,
    messages: MemoryMessageStore(),
    safety: safety,
  );
  return AppSession(
    uid: uid,
    username: uid,
    device: device,
    chat: chat,
    keys: keys,
    safety: safety,
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

Future<(FakeFirebaseFirestore, AppSession, AppSession)> world(
  WidgetTester t,
) async {
  final db = FakeFirebaseFirestore();
  late AppSession alice, bob;
  await t.runAsync(() async {
    for (final u in ['alice', 'bob']) {
      await db.collection('usernames').doc(u).set({'uid': u});
      await db.collection('users').doc(u).set({'username': u});
    }
    alice = await makeSession(db, 'alice');
    bob = await makeSession(db, 'bob');
    await alice.chat.startChat('bob');
  });
  return (db, alice, bob);
}
