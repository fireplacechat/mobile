// "Message not confirmed": what the service reports when a send is not a clear failure, and how it
// is resolved (decision 0009 / UI handoff 1). The message may already have been delivered, so
// nothing here may ever publish a second copy without an explicit decision.
import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'durability_test.dart' show FlakySecretStore, Phone, eventually, fb;

/// A history store that can fail writes, like a full or locked disk.
class FlakyHistory extends MemoryMessageStore {
  int failAdds = 0;
  bool Function(LocalMessage)? failWhen;
  @override
  Future<void> add(LocalMessage m) async {
    if (failAdds > 0 && (failWhen?.call(m) ?? true)) {
      failAdds--;
      throw StateError('history storage unavailable');
    }
    await super.add(m);
  }
}

const chatId = 'alice_bob';

void main() {
  late FakeFirebaseFirestore db;
  late Phone alice, bob;
  late FlakyHistory aliceHistory;

  Future<Phone> makePhone(String uid, MemoryMessageStore store) async {
    final p = Phone(db, uid, FlakySecretStore(), store);
    p.keys = KeyService(db, p.secrets);
    p.device = await p.keys.ensureDevice(uid);
    p.prekeys = PreKeyService(db, p.secrets);
    await p.prekeys.maintain(uid, p.device);
    p.restart();
    return p;
  }

  setUp(() async {
    db = FakeFirebaseFirestore();
    for (final u in ['alice', 'bob']) {
      await db.collection('usernames').doc(u).set({'uid': u});
      await db.collection('users').doc(u).set({'username': u});
    }
    aliceHistory = FlakyHistory();
    alice = await makePhone('alice', aliceHistory);
    bob = await makePhone('bob', MemoryMessageStore());
    await alice.chat.startChat('bob');
    await bob.chat.acceptRequest(chatId);
  });
  tearDown(() async {
    await alice.sub?.cancel();
    await bob.sub?.cancel();
  });

  Future<int> serverCount() async =>
      (await db.collection('chats/$chatId/messages').get()).docs.length;
  Future<List<LocalMessage>> history() => aliceHistory.watch(chatId).first;

  /// The network drops after the server committed: the app is told "unavailable".
  void commitThenLose() => alice.commit = (b) async {
    await b.commit();
    throw fb('unavailable');
  };

  /// The network drops before the server commits anything.
  void loseBeforeCommit() =>
      alice.commit = (_) async => throw fb('unavailable');

  Future<SendNotConfirmedException> sendExpectingUnconfirmed(
    String text,
  ) async {
    try {
      await alice.chat.sendText(chatId, text);
    } on SendNotConfirmedException catch (e) {
      return e;
    }
    fail('expected the send to be reported as not confirmed');
  }

  test('a lost network is reported as publishUnknown with a stable id, and is kept as a warning in history', () async {
    loseBeforeCommit();
    final e = await sendExpectingUnconfirmed('are you there?');
    expect(e.outcome, SendOutcome.publishUnknown);
    expect(e.persisted, isTrue);
    expect(e.body, 'are you there?');
    expect(e.chatId, chatId);
    final h = await history();
    expect(h, hasLength(1));
    expect(h.single.id, e.messageId);
    expect(h.single.status, MessageStatus.unconfirmed);
    expect(h.single.outgoing, isTrue);
    expect(await serverCount(), 0);
  });

  test('checking status never publishes, and absence on the server never proves non-publication', () async {
    loseBeforeCommit();
    final e = await sendExpectingUnconfirmed('hello');
    alice.commit = null;
    for (var i = 0; i < 3; i++) {
      expect(
        await alice.chat.checkSendStatus(chatId, e.messageId),
        SendOutcome.publishUnknown,
      );
    }
    expect(await serverCount(), 0, reason: 'checking never publishes');
    expect(
      (await history()).single.status,
      MessageStatus.unconfirmed,
      reason: 'the warning stays',
    );
  });

  test('if the server does hold the message, Check status confirms it and repairs history', () async {
    commitThenLose();
    final e = await sendExpectingUnconfirmed('it did arrive');
    alice.commit = null;
    expect(await serverCount(), 1);
    expect((await history()).single.status, MessageStatus.unconfirmed);
    expect(
      await alice.chat.checkSendStatus(chatId, e.messageId),
      SendOutcome.confirmed,
    );
    final h = await history();
    expect(h, hasLength(1));
    expect(h.single.status, MessageStatus.ok);
    expect(h.single.id, e.messageId);
    expect(
      await alice.chat.checkSendStatus(chatId, e.messageId),
      SendOutcome.confirmed,
    );
    expect(await serverCount(), 1, reason: 'still exactly one copy');
  });

  test('a message from someone else is never "confirmed" as ours', () async {
    await bob.chat.sendText(chatId, 'from bob');
    final id =
        (await db.collection('chats/$chatId/messages').get()).docs.single.id;
    expect(
      await alice.chat.checkSendStatus(chatId, id),
      SendOutcome.publishUnknown,
    );
  });

  test('sync resolves the warning by itself when our own message turns up on the server', () async {
    commitThenLose();
    await sendExpectingUnconfirmed('delivered after all');
    alice.commit = null;
    alice.sub = alice.chat.startSync(chatId);
    await eventually(
      () async => (await history()).single.status == MessageStatus.ok,
      'warning resolved by sync',
    );
    bob.sub = bob.chat.startSync(chatId);
    await eventually(
      () async => (await bob.bodies(chatId)).contains('delivered after all'),
      'bob receives it',
    );
    expect(
      (await bob.bodies(chatId)).where((b) => b == 'delivered after all'),
      hasLength(1),
    );
  });

  test('if the local write that resolves the warning fails, sync retries it instead of forgetting', () async {
    commitThenLose();
    await sendExpectingUnconfirmed('retry the repair');
    alice.commit = null;
    aliceHistory.failAdds = 1; // the repair write fails once
    alice.sub = alice.chat.startSync(chatId);
    await eventually(
      () async => aliceHistory.failAdds == 0,
      'the repair was attempted',
    );
    expect((await history()).single.status, MessageStatus.unconfirmed);
    await alice.chat.retryDeferred();
    expect(
      (await history()).single.status,
      MessageStatus.ok,
      reason: 'the retry resolved it',
    );
  });

  test('the warning survives an app restart', () async {
    loseBeforeCommit();
    final e = await sendExpectingUnconfirmed('persist me');
    alice.restart();
    alice.commit = null;
    final h = await history();
    expect(h.single.id, e.messageId);
    expect(h.single.status, MessageStatus.unconfirmed);
    expect(
      await alice.chat.checkSendStatus(chatId, e.messageId),
      SendOutcome.publishUnknown,
    );
  });

  test('published but not saved on this phone: reported as such, never as a failure; Save repairs only the history', () async {
    aliceHistory.failAdds = 1;
    late SendNotConfirmedException e;
    try {
      await alice.chat.sendText(chatId, 'sent but unsaved');
      fail('expected an exception');
    } on SendNotConfirmedException catch (x) {
      e = x;
    }
    expect(e.outcome, SendOutcome.publishedLocalSaveFailed);
    expect(e.persisted, isFalse);
    expect(await serverCount(), 1, reason: 'it IS on the server');
    expect(await history(), isEmpty);
    await alice.chat.saveSentLocally(
      chatId: chatId,
      messageId: e.messageId,
      body: e.body,
      sentAt: e.attemptedAt,
    );
    final h = await history();
    expect(h.single.status, MessageStatus.ok);
    expect(h.single.body, 'sent but unsaved');
    expect(await serverCount(), 1, reason: 'saving locally never publishes');
    bob.sub = bob.chat.startSync(chatId);
    await eventually(
      () async => (await bob.bodies(chatId)).contains('sent but unsaved'),
      'bob receives it',
    );
  });

  test('if even the warning cannot be saved, the exception says so and carries the text', () async {
    loseBeforeCommit();
    aliceHistory.failAdds = 1;
    final e = await sendExpectingUnconfirmed('memory only');
    expect(e.outcome, SendOutcome.publishUnknown);
    expect(
      e.persisted,
      isFalse,
      reason: 'the caller must keep the warning in memory',
    );
    expect(e.body, 'memory only');
    expect(await history(), isEmpty);
  });

  test('Send again creates exactly one NEW message with a new id, advances the ratchet normally and clears the old warning', () async {
    loseBeforeCommit();
    final e = await sendExpectingUnconfirmed('maybe');
    alice.commit = null;
    await alice.chat.resendUnconfirmed(
      chatId: chatId,
      messageId: e.messageId,
      body: e.body,
    );
    final h = await history();
    expect(h, hasLength(1));
    expect(h.single.status, MessageStatus.ok);
    expect(h.single.id, isNot(e.messageId));
    expect(await serverCount(), 1);
    bob.sub = bob.chat.startSync(chatId);
    await eventually(
      () async => (await bob.bodies(chatId)).contains('maybe'),
      'bob receives the copy',
    );
    expect((await bob.bodies(chatId)).where((b) => b == 'maybe'), hasLength(1));
  });

  test('Send again after the original DID arrive makes a second copy, because the user chose it', () async {
    commitThenLose();
    final e = await sendExpectingUnconfirmed('twice');
    alice.commit = null;
    await alice.chat.resendUnconfirmed(
      chatId: chatId,
      messageId: e.messageId,
      body: e.body,
    );
    expect(await serverCount(), 2);
    bob.sub = bob.chat.startSync(chatId);
    await eventually(
      () async =>
          (await bob.bodies(chatId)).where((b) => b == 'twice').length == 2,
      'both copies arrive (distinct messages, each decryptable once)',
    );
  });

  test(
    'a definite refusal is an ordinary failure: no warning, no history entry',
    () async {
      alice.commit = (_) async => throw fb('permission-denied');
      await expectLater(
        alice.chat.sendText(chatId, 'denied'),
        throwsA(isA<ChatException>()),
      );
      expect(await history(), isEmpty);
      expect(await serverCount(), 0);
    },
  );

  test('a timeout is as ambiguous as a lost connection', () async {
    alice.commit = (_) async => throw TimeoutException('no answer');
    final e = await sendExpectingUnconfirmed('slow');
    expect(e.outcome, SendOutcome.publishUnknown);
    expect((await history()).single.status, MessageStatus.unconfirmed);
  });

  test('the ratchet is never reused after an unconfirmed send (a gap, not a repeat)', () async {
    await alice.chat.sendText(chatId, 'one');
    loseBeforeCommit();
    await sendExpectingUnconfirmed('two?');
    alice.commit = null;
    await alice.chat.sendText(chatId, 'three');
    final counters = <int>[
      for (final d
          in (await db.collection('chats/$chatId/messages').get()).docs)
        ((d.data()['envelopes'] as Map).values.first as Map)['n'] as int,
    ];
    expect(
      counters.toSet().length,
      counters.length,
      reason: 'counters $counters',
    );
    bob.sub = bob.chat.startSync(chatId);
    await eventually(
      () async => (await bob.bodies(chatId)).contains('three'),
      'delivered across the gap',
    );
  });
}
