import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_crypto.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/ui/chat_list_screen.dart';
import 'package:fireplace/src/ui/chat_screen.dart';
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

class Side {
  Side(this.session, this.prekeys);
  final AppSession session;
  final PreKeyService prekeys;
}

Future<Side> makeSide(FakeFirebaseFirestore db, String uid) async {
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
  return Side(
    AppSession(
      uid: uid,
      username: uid,
      device: device,
      chat: chat,
      keys: keys,
      safety: safety,
      chatsSub: const Stream<void>.empty().listen((_) {}),
      dispose: () async {},
    ),
    prekeys,
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
  late FakeFirebaseFirestore db;
  late Side alice, bob;
  const chatId = 'alice_bob';

  /// Alice's account suddenly has a device under a DIFFERENT identity that messages Bob.
  Future<AccountIdentity> evilMessage(String text) async {
    final evilId = await AccountIdentity.generate();
    final evilKeys = await DeviceKeys.generate();
    final evil = await evilKeys.certify(evilId, 'alice');
    await db.collection('users/alice/devices').doc(evilKeys.deviceId).set({
      ...evil.toFirestore(),
      'createdAt': Timestamp.now(),
    });
    final (s, _) = await Session.initiate(
      local: evilKeys,
      localBundle: evil,
      remote: await bob.prekeys.fetchBundle(bob.session.device.bundle),
    );
    final env = await s.encrypt(
      utf8.encode(jsonEncode({'type': 'text', 'body': text})),
      chatId: chatId,
    );
    await db.collection('chats/$chatId/messages').doc('evil1').set({
      'senderUid': 'alice',
      'senderDevice': evilKeys.deviceId,
      'ts': Timestamp.now(),
      'envelopes': {bob.session.device.keys.deviceId: env.toJson()},
    });
    return evilId;
  }

  Future<void> setUpWorld(WidgetTester t) async {
    db = FakeFirebaseFirestore();
    await t.runAsync(() async {
      for (final u in ['alice', 'bob']) {
        await db.collection('usernames').doc(u).set({'uid': u});
        await db.collection('users').doc(u).set({'username': u});
      }
      alice = await makeSide(db, 'alice');
      bob = await makeSide(db, 'bob');
      await alice.session.chat.startChat('bob');
      await bob.session.chat.acceptRequest(chatId);
      await bob.session.keys.fetchDevices(
        'alice',
      ); // Bob pins Alice's real identity
    });
  }

  testWidgets(
    'a changed contact key shows a warning, holds the message, and trusting it delivers',
    (t) async {
      await setUpWorld(t);
      late AccountIdentity evilId;
      await t.runAsync(
        () async => evilId = await evilMessage('hello from the new key'),
      );
      late StreamSubscription<void> sub;
      await t.runAsync(() async => sub = bob.session.chat.startSync(chatId));
      await t.pumpWidget(host(bob.session, const ChatScreen(chatId: chatId)));
      await settle(t);

      // held, not shown, and the banner explains
      expect(find.byKey(const Key('identityBanner')), findsOneWidget);
      expect(find.textContaining('security code changed'), findsOneWidget);
      expect(find.text('hello from the new key'), findsNothing);

      await t.ensureVisible(find.byKey(const Key('reviewIdentity')));
      await t.pump();
      await t.tap(find.byKey(const Key('reviewIdentity')));
      await t.pumpAndSettle();
      expect(find.text('Security code changed'), findsOneWidget);
      expect(find.textContaining('Previous key'), findsOneWidget);

      // "Keep on hold" changes nothing
      await t.ensureVisible(find.byKey(const Key('keepBlocked')));
      await t.pump();
      await t.tap(find.byKey(const Key('keepBlocked')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('identityBanner')), findsOneWidget);
      expect(find.text('hello from the new key'), findsNothing);
      expect(
        await t.runAsync(() => bob.session.keys.pinnedIdentity('alice')),
        isNot(evilId.publicBytes),
      );

      // explicit trust
      await t.ensureVisible(find.byKey(const Key('reviewIdentity')));
      await t.pump();
      await t.tap(find.byKey(const Key('reviewIdentity')));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('trustNew')));
      await t.pump();
      await t.tap(find.byKey(const Key('trustNew')));
      await settle(t, rounds: 40);
      expect(find.byKey(const Key('identityBanner')), findsNothing);
      expect(find.text('hello from the new key'), findsOneWidget);
      expect(
        await t.runAsync(() => bob.session.keys.pinnedIdentity('alice')),
        evilId.publicBytes,
      );
      await t.runAsync(() => sub.cancel());
    },
  );

  testWidgets('the chat list marks a contact whose key changed', (t) async {
    await setUpWorld(t);
    await t.runAsync(() async => evilMessage('x'));
    late StreamSubscription<void> sub;
    await t.runAsync(() async => sub = bob.session.chat.startSync(chatId));
    await t.pumpWidget(host(bob.session, const ChatListScreen()));
    await settle(t);
    expect(find.byKey(const Key('tileIdentityWarning')), findsOneWidget);
    await t.runAsync(() => sub.cancel());
  });

  testWidgets(
    'sending to a contact whose key changed raises the same warning and sends nothing',
    (t) async {
      await setUpWorld(t);
      // Alice's account gains a device under another identity; Bob tries to write to her.
      await t.runAsync(() async {
        final evilId = await AccountIdentity.generate();
        final k = await DeviceKeys.generate();
        final b = await k.certify(evilId, 'alice');
        await db.collection('users/alice/devices').doc(k.deviceId).set({
          ...b.toFirestore(),
          'createdAt': Timestamp.now(),
        });
        await bob.session.chat
            .sendText(chatId, 'secret')
            .catchError((Object _) {});
      });
      await t.pumpWidget(host(bob.session, const ChatScreen(chatId: chatId)));
      await settle(t);
      expect(find.byKey(const Key('identityBanner')), findsOneWidget);
      expect(
        (await t.runAsync(() => db.collection('chats/$chatId/messages').get()))!
            .docs,
        isEmpty,
      );
    },
  );
}
