import 'dart:async';
import 'dart:io';

import 'package:fireplace/fireplace_services.dart';

import 'package:fireplace/src/app/providers.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/session_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  SessionHarness harness() {
    final h = SessionHarness();
    addTearDown(h.close);
    return h;
  }

  test('chat subscription survives an invalid snapshot', () async {
    final h = harness();
    await h.profile();
    final id = await h.chat('bob');
    await h.db.collection('chats').doc(id).update({'accepted': 'invalid'});
    final s = (await h.open())!;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(s.chat.syncPagesOpened, isEmpty);
    await h.db.collection('chats').doc(id).update({'accepted': true});
    await eventually(() => s.chat.syncPagesOpened.containsKey(id));
  }, tags: 'timing');

  test('signed out returns no session and opens no local data', () async {
    final h = harness();
    expect(await h.open(signedOut: true), isNull);
    expect(h.secrets.reads, isEmpty);
    expect(h.dir.listSync(), isEmpty);
  });

  test(
    'deleting profile refuses initialization before local resources',
    () async {
      final h = harness();
      await h.profile({'deleting': true});
      await expectLater(h.open(), throwsA(isA<AccountDeletionPending>()));
      expect(h.secrets.reads, isEmpty);
      expect(h.dir.listSync(), isEmpty);
    },
  );

  for (final (profile, email, expected) in [
    (
      {'username': 'profile-name'},
      'fred@users.fireplace.invalid',
      'profile-name',
    ),
    (<String, dynamic>{}, 'fred@users.fireplace.invalid', 'fred'),
    (<String, dynamic>{}, null, ''),
  ]) {
    test('session username resolves to "$expected"', () async {
      final h = harness();
      await h.profile(profile);
      final s = (await h.open(user: HarnessUser(email: email)))!;
      expect(s.uid, 'fred');
      expect(s.username, expected);
      expect(s.device.bundle.uid, 'fred');
      expect(s.keys, isNotNull);
      expect(s.safety.uid, 'fred');
      expect(s.chat.peerOf('fred_sarah'), 'sarah');
      expect(s.chatPreferences.available, isTrue);
      expect(s.pushNotifications, isNull);
    });
  }

  test('new signup can publish its profile after sign-in', () async {
    final h = harness();
    final timer = Timer(const Duration(milliseconds: 500), () {
      unawaited(h.profile());
    });
    addTearDown(timer.cancel);
    expect((await h.open())!.username, 'fred');
  }, tags: 'timing');

  test(
    'disposing a built provider closes chat and session close is repeatable',
    () async {
      final h = harness();
      await h.profile();
      final s = (await h.open())!;
      h.disposeContainer();
      final first = s.close();
      expect(identical(first, s.close()), isTrue);
      await first;
      expect(() => s.chat.startSync('fred_sarah'), throwsStateError);
    },
  );

  test(
    'documents current behaviour: unhide alone does not start sync',
    () async {
      final h = harness();
      await h.profile();
      final accepted = await h.chat('bob');
      final hidden = await h.chat('sarah');
      await h.hidden([hidden]);
      final s = (await h.open())!;
      await eventually(() => s.chat.syncPagesOpened.containsKey(accepted));
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await s.safety.unhideChat(hidden);
      expect(await s.safety.hiddenChats(), isNot(contains(hidden)));
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(s.chat.syncPagesOpened.containsKey(hidden), isFalse);
    },
    tags: 'timing',
  );

  for (final trigger in ['chats', 'blocks']) {
    test('unhidden chat starts sync after the next $trigger change', () async {
      final h = harness();
      await h.profile();
      final accepted = await h.chat('bob');
      final hidden = await h.chat('sarah');
      await h.hidden([hidden]);
      final s = (await h.open())!;
      await eventually(() => s.chat.syncPagesOpened.containsKey(accepted));
      await s.safety.unhideChat(hidden);
      if (trigger == 'chats') {
        await h.chat('katy');
      } else {
        await s.safety.block('steve');
      }
      await eventually(() => s.chat.syncPagesOpened.containsKey(hidden));
      expect(s.chat.syncPagesOpened[hidden], 1);
    });
  }

  test('sync eligibility changes on acceptance and blocking', () async {
    final h = harness();
    await h.profile();
    final accepted = await h.chat('bob');
    final incoming = await h.chat('sarah', accepted: false, initiator: 'sarah');
    final blocked = await h.chat('katy');
    final hidden = await h.chat('steve');
    await h.hidden([hidden]);
    await h.db.doc('users/fred/blocks/katy').set({});
    final s = (await h.open())!;
    await eventually(() => s.chat.syncPagesOpened.containsKey(accepted));
    expect(s.chat.syncPagesOpened.keys, unorderedEquals([accepted]));
    await s.safety.unblock('katy');
    await eventually(() => s.chat.syncPagesOpened.containsKey(blocked));
    await s.chat.acceptRequest(incoming);
    await eventually(() => s.chat.syncPagesOpened.containsKey(incoming));
    expect(s.chat.syncPagesOpened.containsKey(hidden), isFalse);
    final delivered = <String>[];
    s.chat.syncObserver = (chatId, ids) {
      if (chatId == blocked) delivered.addAll(ids);
    };
    await s.safety.block('katy');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await h.db.doc('chats/$blocked/messages/after-block').set({
      'senderUid': 'katy',
      'senderDevice': 'example-device',
      'ts': DateTime.now(),
    });
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(delivered, isNot(contains('after-block')));
    expect(await s.chat.watchMessages(blocked).first, isEmpty);
  }, tags: 'timing');

  for (final change in ['block', 'hide', 'dispose']) {
    test('$change during the baseline write prevents starting sync', () async {
      final h = harness();
      final gate = BaselineWriteGate();
      addTearDown(gate.finish);
      await h.profile();
      await gate.run(() async {
        final s = (await h.open())!;
        gate.enabled = true;
        final id = await h.chat('bob');
        await gate.entered.future.timeout(const Duration(seconds: 5));
        expect(s.chat.syncPagesOpened, isEmpty);
        if (change == 'block') {
          await s.safety.block('bob');
        } else if (change == 'hide') {
          await s.safety.hideChat(id);
        } else {
          h.disposeContainer();
        }
        gate.finish();
        if (change == 'dispose') {
          await s.close();
        } else {
          await eventually(() => !s.chatPreferences.needsBaseline(id));
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(s.chat.syncPagesOpened, isEmpty);
      });
    }, tags: 'timing');
  }

  test('a failed sidecar baseline does not prevent chat sync', () async {
    final h = harness();
    final gate = BaselineWriteGate()..fail = true;
    await h.profile();
    await gate.run(() async {
      final s = (await h.open())!;
      gate.enabled = true;
      final id = await h.chat('bob');
      await eventually(() => s.chat.syncPagesOpened.containsKey(id));
      expect(s.chatPreferences.available, isFalse);
    });
  });

  test(
    'history is baselined before sync and later arrivals remain unseen',
    () async {
      final h = harness();
      await h.profile();
      final id = await h.chat('bob');
      final store = await EncryptedFileMessageStore.open(
        dir: Directory('${h.dir.path}/messages_fred'),
        secrets: h.secrets,
        uid: 'fred',
      );
      await store.add(
        LocalMessage(
          id: 'old',
          chatId: id,
          senderUid: 'bob',
          senderDevice: 'example-device',
          outgoing: false,
          sentAt: DateTime.utc(2026, 10, 6),
          body: 'Existing history',
        ),
      );
      await store.close();
      final s = (await h.open())!;
      await eventually(() => s.chat.syncPagesOpened.containsKey(id));
      expect(s.chatPreferences.seen[id], {'old'});
      // The real receiver stores an unsupported envelope as an incoming history entry.
      await h.db.doc('chats/$id/messages/new').set({
        'senderUid': 'bob',
        'senderDevice': 'example-device',
        'ts': DateTime.now(),
      });
      await eventuallyAsync(
        () async => (await s.chat.watchMessages(id).first).length == 2,
      );
      final messages = await s.chat.watchMessages(id).first;
      expect(
        messages
            .where((m) => !s.chatPreferences.seen[id]!.contains(m.id))
            .map((m) => m.id),
        ['new'],
      );
      expect(s.chatPreferences.seen[id], {'old'});
    },
  );

  test(
    'local wipe closes preferences then deletes both keys and history files',
    () async {
      final h = harness();
      await h.profile();
      final id = await h.chat('bob');
      final s = (await h.open())!;
      await eventually(() => s.chat.syncPagesOpened.containsKey(id));
      final done = Completer<void>();
      s.chatPreferences.changes.listen((_) {}, onDone: done.complete);
      var closedBeforeDelete = false;
      h.secrets.beforeDelete = (key) async {
        if (key == 'chatprefskey:fred') {
          await Future<void>.delayed(Duration.zero);
          closedBeforeDelete = done.isCompleted;
        }
      };
      await s.destroyLocalData!();
      expect(closedBeforeDelete, isTrue);
      expect(h.secrets.deletes, ['chatprefskey:fred', 'msgkey:fred']);
      expect(h.secrets.data.containsKey('chatprefskey:fred'), isFalse);
      expect(Directory('${h.dir.path}/messages_fred').existsSync(), isFalse);
    },
  );

  test(
    'late startup failure propagates without starting subscriptions',
    () async {
      final h = harness();
      await h.profile();
      final failure = StateError('test secret read failure');
      h.secrets.beforeRead = (key) async {
        if (key == 'chatprefskey:fred') throw failure;
      };
      await expectLater(h.open(), throwsA(same(failure)));
      expect(h.session, isNull);
      expect(h.secrets.hiddenReads, 0);
      await h.chat('bob');
      await h.db.doc('users/fred/blocks/sarah').set({});
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(h.secrets.hiddenReads, 0);
    },
    tags: 'timing',
  );

  test('disposed provider ignores subsequent chat and block changes', () async {
    final h = harness();
    await h.profile();
    final s = (await h.open())!;
    final id = await h.chat('bob');
    await eventually(() => s.chat.syncPagesOpened.containsKey(id));
    await s.safety.block('bob');
    await s.safety.unblock('bob');
    await eventually(() => s.chat.syncPagesOpened[id] == 2);
    h.disposeContainer();
    await s.close();
    final pages = Map.of(s.chat.syncPagesOpened);
    final reads = h.secrets.hiddenReads;
    await h.chat('sarah');
    await h.db.doc('users/fred/blocks/katy').set({});
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(s.chat.syncPagesOpened, pages);
    expect(h.secrets.hiddenReads, reads);
  }, tags: 'timing');
}
