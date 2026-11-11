import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:fireplace/src/view/safety/requests_screen.dart';
import 'package:fireplace/src/view/safety/blocked_users_screen.dart';
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

void main() {
  testWidgets(
    'recipient sees a request banner, no composer, and accepting opens the chat',
    (t) async {
      final (db, alice, bob) = await world(t);
      await t.runAsync(() => alice.chat.sendText('alice_bob', 'psst'));
      await t.pumpWidget(host(bob, const ChatScreen(chatId: 'alice_bob')));
      await settle(t);
      expect(find.byKey(const Key('requestBanner')), findsOneWidget);
      expect(find.textContaining('@alice wants to chat'), findsOneWidget);
      expect(find.byKey(const Key('composer')), findsNothing);
      expect(find.byKey(const Key('acceptToReplyNote')), findsOneWidget);
      expect(find.text('psst'), findsNothing); // content hidden until accepted

      await t.tap(find.byKey(const Key('acceptRequest')));
      await settle(t);
      expect(find.byKey(const Key('requestBanner')), findsNothing);
      expect(find.byKey(const Key('composer')), findsOneWidget);
      expect(
        (await t.runAsync(() => db.collection('chats').doc('alice_bob').get()))!
            .data()!['accepted'],
        true,
      );
    },
  );

  testWidgets(
    'the sender sees a pending note, then a waiting state after three messages',
    (t) async {
      final (db, alice, _) = await world(t);
      await t.pumpWidget(host(alice, const ChatScreen(chatId: 'alice_bob')));
      await settle(t);
      expect(find.byKey(const Key('composer')), findsOneWidget);
      await t.runAsync(() async {
        for (var i = 0; i < 3; i++) {
          await alice.chat.sendText('alice_bob', 'hello $i');
        }
      });
      await settle(t);
      expect(find.byKey(const Key('waitingNote')), findsOneWidget);
      expect(find.byKey(const Key('composer')), findsNothing);
      expect(
        (await t.runAsync(() => db.collection('chats').doc('alice_bob').get()))!
            .data()!['requestCount'],
        3,
      );
    },
  );

  testWidgets('blocking from the menu asks for confirmation and blocks', (
    t,
  ) async {
    final (db, alice, bob) = await world(t);
    await t.runAsync(() => bob.chat.acceptRequest('alice_bob'));
    await t.pumpWidget(host(alice, const ChatScreen(chatId: 'alice_bob')));
    await settle(t);
    expect(find.byKey(const Key('chatMenu')), findsNothing);
    expect(find.byKey(const Key('verify')), findsOneWidget);
    await t.tap(find.byKey(const Key('chatDetails')));
    await t.pumpAndSettle();
    expect(find.text('Mute'), findsOneWidget);
    expect(find.text('Block User'), findsOneWidget);
    expect(find.text('Report Spam'), findsOneWidget);
    expect(find.byIcon(Icons.notifications_none), findsOneWidget);
    expect(
      t.getTopLeft(find.byKey(const Key('detailsMute'))).dy,
      lessThan(t.getTopLeft(find.byKey(const Key('detailsBlock'))).dy),
    );
    expect(
      t.getTopLeft(find.byKey(const Key('detailsBlock'))).dy,
      lessThan(t.getTopLeft(find.byKey(const Key('detailsReport'))).dy),
    );
    Color labelColor(Key key) => t
        .widget<Text>(
          find.descendant(of: find.byKey(key), matching: find.byType(Text)),
        )
        .style!
        .color!;
    expect(
      labelColor(const Key('detailsBlock')),
      labelColor(const Key('detailsReport')),
    );
    expect(
      labelColor(const Key('detailsMute')),
      isNot(labelColor(const Key('detailsBlock'))),
    );
    await t.tap(find.byKey(const Key('detailsBlock')));
    await t.pumpAndSettle();
    expect(find.text('Block bob?'), findsOneWidget);
    expect(
      find.text('Blocked users will not be able to send you messages.'),
      findsOneWidget,
    );
    await t.tap(find.byKey(const Key('confirmBlock')));
    await settle(t);
    final doc = await t.runAsync(() => db.doc('users/alice/blocks/bob').get());
    expect(doc!.exists, isTrue);
    expect(alice.safety.isBlocked('bob'), isTrue);
  });

  testWidgets('report spam names the account and sends no message text', (
    t,
  ) async {
    final (db, alice, bob) = await world(t);
    await t.runAsync(() => bob.chat.acceptRequest('alice_bob'));
    await t.runAsync(() => bob.chat.sendText('alice_bob', 'buy this now'));
    await t.pumpWidget(host(alice, const ChatScreen(chatId: 'alice_bob')));
    await settle(t);
    await t.tap(find.byKey(const Key('chatDetails')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('detailsReport')));
    await t.pumpAndSettle();
    expect(find.text('Report Spam?'), findsOneWidget);
    expect(
      find.textContaining("can't see the content of any chats"),
      findsOneWidget,
    );
    expect(find.text('Report Spam and Block'), findsOneWidget);
    await t.tap(find.byKey(const Key('confirmReportSpam')));
    await settle(t);
    final doc = await t.runAsync(
      () => db.collection('reports').doc('alice_bob').get(),
    );
    final data = doc!.data()!;
    expect(data.keys.toSet(), {'reporter', 'reported', 'reason', 'createdAt'});
    expect(data['reporter'], 'alice');
    expect(data['reported'], 'bob');
    expect(data['reason'], 'spam');
    expect(
      data.values.map((v) => '$v').join(),
      isNot(contains('buy this now')),
    );
    expect(alice.safety.isBlocked('bob'), isFalse);
    expect(find.text('Reported as spam.'), findsOneWidget);
  });

  testWidgets('Requests screen lists a request and Accept / Ignore work', (
    t,
  ) async {
    final (db, alice, bob) = await world(t);
    await t.runAsync(() => alice.chat.sendText('alice_bob', 'hi'));
    await t.pumpWidget(host(bob, const RequestsScreen()));
    await settle(t);
    expect(find.byKey(const Key('request_alice_bob')), findsOneWidget);
    await t.tap(find.byKey(const Key('ignore_alice_bob')));
    await settle(t);
    expect(find.byKey(const Key('request_alice_bob')), findsNothing);
    expect(await t.runAsync(() => bob.safety.hiddenChats()), {'alice_bob'});
    // restore and accept
    await t.runAsync(() => bob.safety.unhideChat('alice_bob'));
    await t.pumpWidget(const SizedBox()); // drop provider state
    await t.pumpWidget(host(bob, const RequestsScreen()));
    await settle(t);
    await t.tap(find.byKey(const Key('accept_alice_bob')));
    await settle(t);
    expect(
      (await t.runAsync(() => db.collection('chats').doc('alice_bob').get()))!
          .data()!['accepted'],
      true,
    );
  });

  testWidgets('Blocked people screen lists and unblocks', (t) async {
    final (_, alice, _) = await world(t);
    await t.runAsync(() => alice.safety.block('bob'));
    await t.pumpWidget(host(alice, const BlockedUsersScreen()));
    await settle(t);
    expect(find.byKey(const Key('blocked_bob')), findsOneWidget);
    await t.tap(find.byKey(const Key('unblock_bob')));
    await settle(t);
    expect(find.byKey(const Key('blocked_bob')), findsNothing);
    expect(alice.safety.isBlocked('bob'), isFalse);
  });
}
