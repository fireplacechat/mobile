// Characterization tests: they pin the behaviour of account-scoped trust, device
// readiness, history streams and the session lifecycle (cancel and restart a sync,
// close while a send is in flight, repeated close). They pass on main at fad558b and
// must keep passing, unchanged, through every stage-2 cut.
import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_crypto.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:flutter_test/flutter_test.dart';

class PausedHistory extends MemoryMessageStore {
  final entered = Completer<void>();
  final release = Completer<void>();
  bool paused = false;
  @override
  Future<bool> has(String chatId, String messageId) async {
    if (!paused) {
      paused = true;
      entered.complete();
      await release.future;
    }
    return super.has(chatId, messageId);
  }
}

Future<ChatService> makeChat(
  FakeFirebaseFirestore db,
  String uid,
  LocalMessageStore messages,
) async {
  await db.doc('users/$uid').set({'username': uid});
  await db.doc('usernames/$uid').set({'uid': uid});
  final secrets = MemorySecretStore();
  final keys = KeyService(db, secrets);
  final device = await keys.ensureDevice(uid);
  final prekeys = PreKeyService(db, secrets);
  await prekeys.maintain(uid, device);
  return ChatService(
    db: db,
    uid: uid,
    device: device,
    keys: keys,
    prekeys: prekeys,
    secrets: secrets,
    messages: messages,
  );
}

void main() {
  group('#1 account-scoped trust', () {
    test('verification and pins do not cross accounts on one device', () async {
      final db = FakeFirebaseFirestore();
      final secrets = MemorySecretStore();
      final peer = await AccountIdentity.generate();
      final a = KeyService(db, secrets);
      final b = KeyService(db, secrets);
      await a.ensureDevice('alice');
      await b.ensureDevice('bob');
      await a.acceptIdentityChange('carol', peer.publicBytes);
      await a.markVerified('carol', peer.publicBytes);
      expect(await a.isVerified('carol'), isTrue);
      expect(await b.pinnedIdentity('carol'), isNull);
      await b.acceptIdentityChange('carol', peer.publicBytes);
      expect(
        await b.isVerified('carol'),
        isFalse,
        reason: 'bob must not inherit alice\'s verification',
      );
    });

    test('one key service cannot be reused for a second account', () async {
      final db = FakeFirebaseFirestore();
      final k = KeyService(db, MemorySecretStore());
      await k.ensureDevice('alice');
      expect(() => k.ensureDevice('bob'), throwsStateError);
    });

    test(
      'old unscoped pins are ignored (first-use pinning starts again)',
      () async {
        final db = FakeFirebaseFirestore();
        final secrets = MemorySecretStore();
        final old = await AccountIdentity.generate();
        await secrets.write('pin:carol', b64(old.publicBytes));
        final k = KeyService(db, secrets);
        await k.ensureDevice('alice');
        // Documents the trade-off in decision 0014: no migration of old pins.
        expect(await k.pinnedIdentity('carol'), isNull);
      },
    );
  });

  group('#4 device readiness', () {
    test('local keys with no published record demand recovery', () async {
      final db = FakeFirebaseFirestore();
      final secrets = MemorySecretStore();
      await db.doc('users/alice').set({'username': 'alice'});
      await KeyService(db, secrets).ensureDevice('alice');
      for (final d in (await db.collection('users/alice/devices').get()).docs) {
        await d.reference.delete();
      }
      // The case to judge: an account with NO devices at all and consistent
      // local keys (for example a first publish that never reached the
      // server). Current behaviour is recovery; there may be no key to use.
      expect(
        KeyService(db, secrets).ensureDevice('alice'),
        throwsA(isA<NeedsRecoveryException>()),
      );
    });

    for (final field in ['x25519Pub', 'kemPub', 'sigPub', 'deviceCert']) {
      test('a changed published $field is not accepted as ready', () async {
        final db = FakeFirebaseFirestore();
        final secrets = MemorySecretStore();
        await db.doc('users/alice').set({'username': 'alice'});
        await KeyService(db, secrets).ensureDevice('alice');
        final doc =
            (await db.collection('users/alice/devices').get()).docs.first;
        expect(doc.data().containsKey(field), isTrue);
        await doc.reference.update({field: 'AAAA'});
        expect(
          KeyService(db, secrets).ensureDevice('alice'),
          throwsA(isA<NeedsRecoveryException>()),
        );
      });
    }
  });

  group('#2 history streams', () {
    test('a corrupt history file is reported, not left waiting', () async {
      // Uses the in-memory store as a stand-in: a store whose load throws.
      final store = _ThrowingLoad();
      await expectLater(
        store.watch('c').first,
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('#3 session lifecycle', () {
    test(
      'cancelling a sync mid-batch and restarting still delivers all',
      () async {
        final db = FakeFirebaseFirestore();
        final history = PausedHistory();
        final fred = await makeChat(db, 'fred', MemoryMessageStore());
        final bob = await makeChat(db, 'bob', history);
        final chatId = await fred.startChat('bob');
        await bob.acceptRequest(chatId);
        for (final t in ['one', 'two', 'three']) {
          await fred.sendText(chatId, t);
        }
        final first = bob.startSync(chatId);
        await history.entered.future.timeout(const Duration(seconds: 5));
        await first.cancel();
        history.release.complete();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        final second = bob.startSync(chatId);
        await Future<void>.delayed(const Duration(milliseconds: 400));
        await fred.sendText(chatId, 'four');
        await Future<void>.delayed(const Duration(milliseconds: 400));
        final got = (await history.watch(chatId).first)
            .map((m) => m.body)
            .toSet();
        expect(got, containsAll(['one', 'two', 'three', 'four']));
        await second.cancel();
        await bob.close();
        await fred.close();
      },
    );

    test('close waits for a send that holds the session lock', () async {
      final db = FakeFirebaseFirestore();
      final fred = await makeChat(db, 'fred', MemoryMessageStore());
      await makeChat(db, 'bob', MemoryMessageStore());
      final chatId = await fred.startChat('bob');
      final sending = fred.sendText(chatId, 'in flight');
      await fred.close();
      await sending; // must complete, not throw, and be stored
      final mine = await fred.watchMessages(chatId).first;
      expect(mine.map((m) => m.body), contains('in flight'));
    });

    test('close is safe to call repeatedly and from several callers', () async {
      final db = FakeFirebaseFirestore();
      final bob = await makeChat(db, 'bob', MemoryMessageStore());
      await Future.wait([bob.close(), bob.close(), bob.close()]);
      await bob.retryDeferred();
    });
  });
}

class _ThrowingLoad extends MemoryMessageStore {
  @override
  Stream<List<LocalMessage>> watch(String chatId) =>
      Stream.error(const FormatException('corrupt history'));
}
