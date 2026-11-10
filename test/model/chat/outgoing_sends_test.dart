// The outgoing queue: a message leaves the composer at once, is sent in
// order, and one that fails waits for the person to send it again or delete
// it. Nothing is ever sent again without being asked.
import 'dart:async';

import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/chat/message_controls.dart';
import 'package:fireplace/src/model/chat/outgoing_sends.dart';
import 'package:fireplace/src/model/chat/pending_sends.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

const chat = 'alice_fred';
Future<void> settle() => Future<void>.delayed(Duration.zero);

class Harness {
  Harness() {
    container = ProviderContainer(overrides: f.overrides);
    addTearDown(container.dispose);
    addTearDown(f.session.close);
    container.listen(outgoingSendsProvider, (_, _) {});
    container.listen(pendingLocalSendsProvider, (_, _) {});
  }
  final f = UiFixture();
  late final ProviderContainer container;
  OutgoingSends get queue => container.read(outgoingSendsProvider.notifier);
  List<OutgoingSend> get sends => container.read(outgoingSendsProvider);
}

SendNotConfirmedException uncertain({required bool persisted}) =>
    SendNotConfirmedException(
      outcome: SendOutcome.publishUnknown,
      chatId: chat,
      messageId: 'server-id',
      body: 'hello',
      attemptedAt: fixtureTime,
      persisted: persisted,
    );

void main() {
  test(
    'a message shows as being sent until it is, then leaves the queue',
    () async {
      final h = Harness();
      h.f.chat.sendHold = Completer<void>();
      final id = h.queue.enqueue(chat, 'hello');
      expect(h.sends.single.id, id);
      expect(h.sends.single.state, OutgoingState.sending);
      expect(h.sends.single.body, 'hello');
      expect(h.sends.single.createdAt, fixtureTime);
      await settle();
      expect(h.f.chat.sends, ['hello']);
      h.f.chat.sendHold!.complete();
      await settle();
      expect(h.sends, isEmpty);
    },
  );

  test('messages are sent one at a time, in the order written', () async {
    final h = Harness();
    h.f.chat.sendHold = Completer<void>();
    h.queue
      ..enqueue(chat, 'one')
      ..enqueue(chat, 'two')
      ..enqueue(chat, 'three');
    await settle();
    expect(h.f.chat.sends, ['one'], reason: 'the next waits for the first');
    expect(h.sends.map((s) => s.body), ['one', 'two', 'three']);
    h.f.chat.sendHold!.complete();
    await settle();
    await settle();
    expect(h.f.chat.sends, ['one', 'two', 'three']);
    expect(h.sends, isEmpty);
  });

  test('a reply is sent as a reply', () async {
    final h = Harness();
    await h.f.seed();
    h.queue.enqueue(chat, 'Lovely', replyTarget: '5');
    await settle();
    await settle();
    expect(h.f.chat.replies, [('5', 'Lovely')]);
    expect(h.sends, isEmpty);
  });

  test(
    'a refused send stays as failed with its reason and is not retried',
    () async {
      final h = Harness();
      h.f.chat.sendError = ChatException('Nothing was sent. Try again later.');
      final id = h.queue.enqueue(chat, 'hello');
      await settle();
      final failed = h.sends.single;
      expect(failed.id, id);
      expect(failed.state, OutgoingState.failed);
      expect(failed.error, 'Nothing was sent. Try again later.');
      expect(failed.mayHaveArrived, isFalse);
      expect(failed.body, 'hello');
      await settle();
      expect(h.f.chat.sends, ['hello'], reason: 'one attempt only');
    },
  );

  test('a failed message does not hold up the ones after it', () async {
    final h = Harness();
    h.f.chat.sendError = ChatException('Refused');
    h.queue.enqueue(chat, 'one');
    await settle();
    h.f.chat.sendError = null;
    h.queue.enqueue(chat, 'two');
    await settle();
    expect(h.sends.map((s) => (s.body, s.state)), [
      ('one', OutgoingState.failed),
    ]);
    expect(h.f.chat.sends, ['one', 'two']);
  });

  test('send again is a decision: it retries once and can succeed', () async {
    final h = Harness();
    h.f.chat.sendError = ChatException('Refused');
    final id = h.queue.enqueue(chat, 'hello');
    await settle();
    h.f.chat.sendError = null;
    h.queue.sendAgain(id);
    expect(h.sends.single.state, OutgoingState.sending);
    expect(h.sends.single.error, isNull);
    await settle();
    expect(h.f.chat.sends, ['hello', 'hello']);
    expect(h.sends, isEmpty);
    // Asking again for something no longer waiting does nothing.
    h.queue.sendAgain(id);
    await settle();
    expect(h.f.chat.sends, hasLength(2));
  });

  test(
    'delete removes a failed message; one being sent cannot be recalled',
    () async {
      final h = Harness();
      h.f.chat.sendHold = Completer<void>();
      final id = h.queue.enqueue(chat, 'hello');
      await settle();
      h.queue.delete(id);
      expect(h.sends, hasLength(1), reason: 'it is already on its way');
      h.f.chat
        ..sendError = ChatException('Refused')
        ..sendHold!.complete();
      await settle();
      expect(h.sends.single.state, OutgoingState.failed);
      h.queue.delete(id);
      expect(h.sends, isEmpty);
    },
  );

  test(
    'an unexpected error may have arrived and says so in plain words',
    () async {
      final h = Harness();
      h.f.chat.sendError = StateError('secret internals');
      h.queue.enqueue(chat, 'hello');
      await settle();
      final failed = h.sends.single;
      expect(failed.state, OutgoingState.failed);
      expect(failed.mayHaveArrived, isTrue);
      expect(failed.error, OutgoingSends.uncertainText);
      expect(failed.error, isNot(contains('secret')));
    },
  );

  test(
    'a changed security code fails the send and carries the new identity',
    () async {
      final h = Harness();
      h.f.chat.sendError = IdentityChangedException('fred', [7]);
      h.queue.enqueue(chat, 'hello');
      await settle();
      final failed = h.sends.single;
      expect(failed.state, OutgoingState.failed);
      expect(failed.error, OutgoingSends.identityText);
      expect(failed.identity!.peerUid, 'fred');
    },
  );

  for (final persisted in [true, false]) {
    test(
      'a send that may have been delivered leaves the queue for the not-confirmed record (persisted=$persisted)',
      () async {
        final h = Harness();
        h.f.chat.sendError = uncertain(persisted: persisted);
        h.queue.enqueue(chat, 'hello');
        await settle();
        // No failed bubble with a one-tap "send again": the history (or the
        // in-memory record) shows it with its own warning and decisions.
        expect(h.sends, isEmpty);
        expect(
          h.container.read(pendingLocalSendsProvider).keys,
          persisted ? isEmpty : ['$chat/server-id'],
        );
      },
    );
  }

  test('conversations do not wait for each other', () async {
    final h = Harness();
    h.f.chat.sendHold = Completer<void>();
    h.queue
      ..enqueue(chat, 'to fred')
      ..enqueue('alice_bob', 'to bob');
    await settle();
    expect(h.f.chat.sends, ['to fred', 'to bob']);
    h.f.chat.sendHold!.complete();
    await settle();
    expect(h.sends, isEmpty);
  });

  test(
    'the queue belongs to the account and is emptied when it changes',
    () async {
      final f = UiFixture();
      addTearDown(f.session.close);
      final container = ProviderContainer(
        overrides: [
          messageControlNowProvider.overrideWithValue(() => fixtureTime),
          appSessionProvider.overrideWith(
            (ref) async => ref.watch(_signedIn) ? f.session : null,
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(outgoingSendsProvider, (_, _) {});
      container.listen(appSessionProvider, (_, _) {});
      await container.read(appSessionProvider.future);
      f.chat.sendError = ChatException('Refused');
      container.read(outgoingSendsProvider.notifier).enqueue(chat, 'private');
      await settle();
      expect(container.read(outgoingSendsProvider), hasLength(1));
      container.read(_signedIn.notifier).signOut();
      await container.read(appSessionProvider.future);
      await settle();
      expect(container.read(outgoingSendsProvider), isEmpty);
    },
  );

  test('an old session cannot drain or unlock a new session queue', () async {
    final f = UiFixture();
    addTearDown(f.session.close);
    final container = ProviderContainer(
      overrides: [
        messageControlNowProvider.overrideWithValue(() => fixtureTime),
        appSessionProvider.overrideWith(
          (ref) async => ref.watch(_signedIn) ? f.session : null,
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(outgoingSendsProvider, (_, _) {});
    await container.read(appSessionProvider.future);
    final queue = container.read(outgoingSendsProvider.notifier);
    final oldSend = Completer<void>();
    f.chat.sendHold = oldSend;
    queue.enqueue(chat, 'old session');
    await settle();

    container.read(_signedIn.notifier).signOut();
    await container.read(appSessionProvider.future);
    expect(container.read(outgoingSendsProvider), isEmpty);
    container.read(_signedIn.notifier).signIn();
    await container.read(appSessionProvider.future);
    expect(container.read(outgoingSendsProvider), isEmpty);

    final newSend = Completer<void>();
    f.chat.sendHold = newSend;
    queue.enqueue(chat, 'new session first');
    await settle();
    oldSend.complete();
    await settle();
    queue.enqueue(chat, 'new session second');
    await settle();
    expect(f.chat.sends, [
      'old session',
      'new session first',
    ], reason: 'the old completion must not restart or unlock the new drain');
    newSend.complete();
    await settle();
    await settle();
    expect(f.chat.sends, [
      'old session',
      'new session first',
      'new session second',
    ]);
    expect(container.read(outgoingSendsProvider), isEmpty);
  });
}

class _SignedIn extends Notifier<bool> {
  @override
  bool build() => true;
  void signOut() => state = false;
  void signIn() => state = true;
}

final _signedIn = NotifierProvider<_SignedIn, bool>(_SignedIn.new);
