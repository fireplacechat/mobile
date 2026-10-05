// Chat screen: "Message not confirmed" (UI handoff 1). A send that may have been delivered is never
// shown as a plain failure, never leaves the draft poised to resend, and only an explicit
// decision can create a second copy.
import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/ui/chat_screen.dart';
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
  testWidgets(
    'a lost network shows "Message not confirmed", moves the draft into the bubble and clears the composer',
    (t) async {
      final r = await open(t);
      loseBeforeCommit(r);
      await typeAndSend(t, 'hello hearth');
      expect(find.text('Message not confirmed'), findsOneWidget);
      expect(find.textContaining('may have reached them'), findsOneWidget);
      expect(
        find.text('hello hearth'),
        findsOneWidget,
        reason: 'the attempted message is in a pending bubble',
      );
      expect(composerText(t), isEmpty, reason: 'nothing poised to resend');
      expect(find.textContaining('Could not send'), findsNothing);
      expect(find.byKey(const Key('checkSendStatus')), findsOneWidget);
      expect(find.byKey(const Key('resendUnconfirmed')), findsOneWidget);
      // The warning announces itself once, as a live region.
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.liveRegion == true,
        ),
        findsWidgets,
      );
    },
  );

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
    expect(find.text('Message not confirmed'), findsOneWidget);
    expect(composerText(t), 'next thing I am typing');
  });

  testWidgets(
    'Check status when the server has nothing keeps the warning and publishes nothing',
    (t) async {
      final r = await open(t);
      loseBeforeCommit(r);
      await typeAndSend(t, 'maybe');
      r.alice.commit = null;
      await t.tap(find.byKey(const Key('checkSendStatus')));
      await settle(t);
      expect(find.text('Message not confirmed'), findsOneWidget);
      expect(find.byKey(const Key('checkNote')), findsOneWidget);
      expect(
        find.textContaining('may or may not have been delivered'),
        findsOneWidget,
      );
      await t.tap(find.byKey(const Key('checkSendStatus')));
      await settle(t);
      expect(
        await t.runAsync(r.serverCount),
        0,
        reason: 'checking never publishes',
      );
    },
  );

  testWidgets(
    'Check status resolves the warning when the server holds the message',
    (t) async {
      final r = await open(t);
      commitThenLose(r);
      await typeAndSend(t, 'it arrived');
      r.alice.commit = null;
      expect(find.text('Message not confirmed'), findsOneWidget);
      await t.tap(find.byKey(const Key('checkSendStatus')));
      await settle(t);
      expect(find.text('Message not confirmed'), findsNothing);
      expect(find.text('it arrived'), findsOneWidget);
      expect(await t.runAsync(r.serverCount), 1);
    },
  );

  testWidgets(
    'Send again asks first, then sends one new copy and clears the warning',
    (t) async {
      final r = await open(t);
      loseBeforeCommit(r);
      await typeAndSend(t, 'again please');
      r.alice.commit = null;
      await t.tap(find.byKey(const Key('resendUnconfirmed')));
      await settle(t, rounds: 5);
      expect(find.text('Send another copy?'), findsOneWidget);
      expect(
        find.textContaining('original may already have been delivered'),
        findsOneWidget,
      );
      // Cancel does nothing.
      await t.tap(find.byKey(const Key('cancelResend')));
      await settle(t, rounds: 5);
      expect(await t.runAsync(r.serverCount), 0);
      expect(find.text('Message not confirmed'), findsOneWidget);
      // The explicit choice sends exactly one new message.
      await t.tap(find.byKey(const Key('resendUnconfirmed')));
      await settle(t, rounds: 5);
      await t.tap(find.byKey(const Key('confirmResend')));
      await settle(t);
      expect(await t.runAsync(r.serverCount), 1);
      expect(find.text('Message not confirmed'), findsNothing);
      expect(find.text('again please'), findsOneWidget);
    },
  );

  testWidgets(
    'published but not saved: says so, never offers a resend, and Save repairs only the history',
    (t) async {
      final r = await open(t);
      r.history.failAdds = 1;
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
      r.history.failAdds = 1;
      await typeAndSend(t, 'memory only');
      expect(find.text('Message not confirmed'), findsOneWidget);
      expect(find.text('memory only'), findsOneWidget);
    },
  );

  testWidgets(
    'an ordinary refusal is still a plain, retryable failure (draft kept)',
    (t) async {
      final r = await open(t);
      r.alice.commit = (_) async => throw fb('permission-denied');
      await typeAndSend(t, 'blocked?');
      expect(find.text('Message not confirmed'), findsNothing);
      expect(composerText(t), 'blocked?');
    },
  );

  testWidgets(
    'the warning and all actions stay usable on a narrow screen at 200% text',
    (t) async {
      final r = await open(t, textScale: 2, size: const Size(320, 700));
      loseBeforeCommit(r);
      await typeAndSend(t, 'narrow');
      expect(t.takeException(), isNull, reason: 'no overflow');
      expect(find.text('Message not confirmed'), findsOneWidget);
      expect(find.byKey(const Key('checkSendStatus')), findsOneWidget);
      expect(find.byKey(const Key('resendUnconfirmed')), findsOneWidget);
    },
  );
}
