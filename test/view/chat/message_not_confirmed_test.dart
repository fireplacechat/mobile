// Chat screen: a send whose outcome is not known (decision 0059). The message
// stays in the conversation as any message on its way, the app finishes
// sending it by itself, and it can never arrive twice. Only a message that
// was given up on says "Not sent".
import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/chat/send_resume.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../model/chat/durability_test.dart' show FlakySecretStore, Phone, fb;
import '../../model/chat/send_outcome_test.dart' show FlakyHistory;

const chatId = 'alice_bob';

class Rig {
  Rig(this.db, this.alice, this.history, this.session);
  final FakeFirebaseFirestore db;
  final Phone alice;
  final FlakyHistory history;
  final AppSession session;
  Future<int> serverCount() async =>
      (await db.collection('chats/$chatId/messages').get()).docs.length;
}

Future<void> settle(WidgetTester t, {int rounds = 25}) async {
  for (var i = 0; i < rounds; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await t.pump();
  }
}

/// Lets one wait between tries pass, and what follows it finish.
Future<void> nextTry(WidgetTester t) async {
  await t.pump(const Duration(seconds: 5));
  await settle(t);
}

const notSent = 'Not sent. Tap for options.';

Future<Rig> open(
  WidgetTester t, {
  double textScale = 1,
  Size size = const Size(800, 1800),
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  late Rig rig;
  await t.runAsync(() async {
    final db = FakeFirebaseFirestore();
    for (final u in ['alice', 'bob']) {
      await db.collection('usernames').doc(u).set({'uid': u});
      await db.collection('users').doc(u).set({'username': u});
    }
    final history = FlakyHistory();
    Future<Phone> make(String uid, MemoryMessageStore store) async {
      final p = Phone(db, uid, FlakySecretStore(), store);
      p.keys = KeyService(db, p.secrets);
      p.device = await p.keys.ensureDevice(uid);
      p.prekeys = PreKeyService(db, p.secrets);
      await p.prekeys.maintain(uid, p.device);
      p.restart();
      return p;
    }

    final alice = await make('alice', history);
    final bob = await make('bob', MemoryMessageStore());
    await alice.chat.startChat('bob');
    await bob.chat.acceptRequest(chatId);
    final safety = SafetyService(db, alice.secrets, 'alice');
    final session = AppSession(
      uid: 'alice',
      username: 'alice',
      device: alice.device,
      chat: alice.chat,
      keys: alice.keys,
      safety: safety,
      chatsSub: const Stream<void>.empty().listen((_) {}),
      dispose: () async {},
    );
    rig = Rig(db, alice, history, session);
  });
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        authUserProvider.overrideWithValue(const AsyncData(null)),
        appSessionProvider.overrideWithValue(AsyncData(rig.session)),
        firestoreProvider.overrideWithValue(rig.db),
      ],
      child: MaterialApp(
        theme: fireplaceTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const ChatScreen(chatId: chatId),
      ),
    ),
  );
  await settle(t);
  return rig;
}

Future<void> typeAndSend(WidgetTester t, String text) async {
  await t.enterText(find.byKey(const Key('composer')), text);
  await t.pump();
  await t.tap(find.byKey(const Key('send')));
  await settle(t);
}

void loseBeforeCommit(Rig r) =>
    r.alice.commit = (_) async => throw fb('unavailable');
void commitThenLose(Rig r) => r.alice.commit = (b) async {
  await b.commit();
  throw fb('unavailable');
};

String composerText(WidgetTester t) =>
    t.widget<TextField>(find.byKey(const Key('composer'))).controller!.text;

void main() {
  // One wait of five seconds between tries, then give up: enough to tell
  // "still trying" from "given up" without a test running for a minute.
  setUp(() => SendResume.pauses = const [Duration(seconds: 5)]);
  tearDown(
    () => SendResume.pauses = const [
      Duration(seconds: 5),
      Duration(seconds: 20),
      Duration(seconds: 60),
    ],
  );

  Future<List<LocalMessage>> stored(WidgetTester t, Rig r) async =>
      (await t.runAsync(() => r.history.watch(chatId).first))!;

  testWidgets('a lost network: the message stays as a bubble with no warning, '
      'and is sent by itself, once, when the network is back', (t) async {
    final r = await open(t);
    loseBeforeCommit(r);
    await typeAndSend(t, 'hello hearth');
    expect(find.text('hello hearth'), findsOneWidget);
    expect(find.text('Message not confirmed'), findsNothing);
    expect(find.byKey(const Key('checkSendStatus')), findsNothing);
    expect(find.byKey(const Key('resendUnconfirmed')), findsNothing);
    expect(find.text(notSent), findsNothing, reason: 'still trying');
    expect(composerText(t), isEmpty);
    expect(await t.runAsync(r.serverCount), 0);
    final id = (await stored(t, r)).single.id;

    r.alice.commit = null; // the network is back
    await nextTry(t);
    expect(await t.runAsync(r.serverCount), 1);
    final docs = await t.runAsync(
      () => r.db.collection('chats/$chatId/messages').get(),
    );
    expect(docs!.docs.single.id, id, reason: 'the same message, not a copy');
    final sent = (await stored(t, r)).single;
    expect(sent.id, id);
    expect(sent.status, MessageStatus.ok);
    expect(find.text('hello hearth'), findsOneWidget);
    expect(find.text(notSent), findsNothing);
  });

  testWidgets('a message that did arrive is settled without sending again', (
    t,
  ) async {
    final r = await open(t);
    commitThenLose(r);
    await typeAndSend(t, 'it arrived');
    // The first look at the server finds it.
    expect(await t.runAsync(r.serverCount), 1);
    expect((await stored(t, r)).single.status, MessageStatus.ok);
    expect(find.text('it arrived'), findsOneWidget);
    expect(find.text('Message not confirmed'), findsNothing);
    expect(find.text(notSent), findsNothing);
    await nextTry(t);
    expect(await t.runAsync(r.serverCount), 1);
  });

  testWidgets('edits made while the send is in flight survive', (t) async {
    final r = await open(t);
    final gate = Completer<void>();
    r.alice.commit = (_) async {
      await gate.future;
      throw fb('unavailable');
    };
    await t.enterText(find.byKey(const Key('composer')), 'first draft');
    await t.pump();
    await t.tap(find.byKey(const Key('send')));
    await t.pump();
    await t.enterText(
      find.byKey(const Key('composer')),
      'next thing I am typing',
    );
    await t.pump();
    gate.complete();
    await settle(t);
    expect(find.text('first draft'), findsOneWidget);
    expect(find.text('Message not confirmed'), findsNothing);
    expect(composerText(t), 'next thing I am typing');
    r.alice.commit = null;
    await nextTry(t);
    expect(await t.runAsync(r.serverCount), 1);
  });

  testWidgets('when the tries run out the bubble says Not sent; Send again '
      'sends that same message', (t) async {
    final r = await open(t);
    loseBeforeCommit(r);
    await typeAndSend(t, 'again please');
    await nextTry(t); // the second and last try fails too
    expect(find.text(notSent), findsOneWidget);
    expect(find.text('Message not confirmed'), findsNothing);
    expect(await t.runAsync(r.serverCount), 0);
    final id = (await stored(t, r)).single.id;

    await t.tap(find.text('again please'));
    await settle(t, rounds: 5);
    expect(find.byKey(const Key('failedSendDialog')), findsOneWidget);
    // Cancel does nothing.
    await t.tap(find.byKey(const Key('failedSendCancel')));
    await settle(t, rounds: 5);
    expect(await t.runAsync(r.serverCount), 0);
    expect(find.text(notSent), findsOneWidget);

    r.alice.commit = null;
    await t.tap(find.text('again please'));
    await settle(t, rounds: 5);
    await t.tap(find.byKey(const Key('failedSendAgain')));
    await settle(t);
    final docs = await t.runAsync(
      () => r.db.collection('chats/$chatId/messages').get(),
    );
    expect(docs!.docs.single.id, id);
    expect(find.text(notSent), findsNothing);
    expect(find.text('again please'), findsOneWidget);
    expect((await stored(t, r)).single.status, MessageStatus.ok);
  });

  testWidgets('a message that was not sent can be deleted', (t) async {
    final r = await open(t);
    loseBeforeCommit(r);
    await typeAndSend(t, 'never mind');
    await nextTry(t);
    await t.tap(find.text('never mind'));
    await settle(t, rounds: 5);
    await t.tap(find.byKey(const Key('failedSendDelete')));
    await settle(t);
    expect(find.text('never mind'), findsNothing);
    expect(await stored(t, r), isEmpty);
    expect(await t.runAsync(r.serverCount), 0);
  });

  testWidgets('a message left unsent long ago is not sent by itself', (
    t,
  ) async {
    final r = await open(t);
    await t.runAsync(
      () => r.history.add(
        LocalMessage(
          id: 'old',
          chatId: chatId,
          senderUid: 'alice',
          senderDevice: r.alice.device.keys.deviceId,
          outgoing: true,
          sentAt: DateTime.now().subtract(const Duration(days: 3)),
          body: 'from last week',
          status: MessageStatus.unconfirmed,
        ),
      ),
    );
    await settle(t);
    expect(find.text('from last week'), findsOneWidget);
    expect(find.text(notSent), findsOneWidget);
    expect(await t.runAsync(r.serverCount), 0);
  });

  testWidgets(
    'published but not saved: says so, never offers a resend, and Save repairs only the history',
    (t) async {
      final r = await open(t);
      r.history.failAdds = 2; // before publishing, and after
      await typeAndSend(t, 'sent but unsaved');
      expect(find.text('Sent — could not save on this device'), findsOneWidget);
      expect(
        find.text('Your message was sent. Do not send it again.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('saveOnDevice')), findsOneWidget);
      expect(find.byKey(const Key('resendUnconfirmed')), findsNothing);
      expect(find.byKey(const Key('checkSendStatus')), findsNothing);
      expect(find.text('sent but unsaved'), findsOneWidget);
      expect(await t.runAsync(r.serverCount), 1);
      await t.tap(find.byKey(const Key('saveOnDevice')));
      await settle(t);
      expect(find.text('Sent — could not save on this device'), findsNothing);
      expect(find.text('sent but unsaved'), findsOneWidget);
      expect(
        await t.runAsync(r.serverCount),
        1,
        reason: 'saving never publishes',
      );
    },
  );

  testWidgets(
    'if even the warning cannot be saved, it is kept in memory and cannot be dismissed silently',
    (t) async {
      final r = await open(t);
      loseBeforeCommit(r);
      r.history.failAdds = 2; // before publishing, and the warning
      await typeAndSend(t, 'memory only');
      expect(find.text('Message not confirmed'), findsOneWidget);
      expect(find.text('memory only'), findsOneWidget);
    },
  );

  testWidgets(
    'an ordinary refusal is a plain failure: a not-sent bubble that can be sent again',
    (t) async {
      final r = await open(t);
      r.alice.commit = (_) async => throw fb('permission-denied');
      await typeAndSend(t, 'blocked?');
      expect(find.text('Message not confirmed'), findsNothing);
      expect(composerText(t), isEmpty);
      expect(find.text('blocked?'), findsOneWidget);
      expect(find.text('Not sent. Tap for options.'), findsOneWidget);
    },
  );

  testWidgets(
    'a message that was not sent stays usable on a narrow screen at 200% text',
    (t) async {
      final r = await open(t, textScale: 2, size: const Size(320, 700));
      loseBeforeCommit(r);
      await typeAndSend(t, 'narrow');
      await nextTry(t);
      expect(t.takeException(), isNull, reason: 'no overflow');
      expect(find.textContaining('Not sent'), findsOneWidget);
      await t.tap(find.text('narrow'));
      await settle(t, rounds: 5);
      expect(find.byKey(const Key('failedSendAgain')), findsOneWidget);
      expect(t.takeException(), isNull, reason: 'no overflow');
    },
  );
}
