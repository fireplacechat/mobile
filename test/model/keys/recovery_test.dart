import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_crypto.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:flutter_test/flutter_test.dart';

class Phone {
  Phone(this.db, this.uid) : secrets = MemorySecretStore() {
    keys = KeyService(db, secrets);
    recovery = RecoveryService(db, secrets, keys);
  }
  final FakeFirebaseFirestore db;
  final String uid;
  final MemorySecretStore secrets;
  late final KeyService keys;
  late final RecoveryService recovery;
}

void main() {
  late FakeFirebaseFirestore db;
  setUp(() => db = FakeFirebaseFirestore());

  group('recovery key', () {
    test(
      'backup, then a fresh install restores the same identity as a new device',
      () async {
        final old = Phone(db, 'alice');
        final oldDev = await old.keys.ensureDevice('alice');
        expect(await old.recovery.hasBackup('alice'), isFalse);
        final rk = await old.recovery.createBackup('alice', oldDev.identity);
        expect(await old.recovery.hasBackup('alice'), isTrue);
        // server never sees the identity in clear
        final stored =
            (await db.collection('users/alice/private').doc('backup').get())
                .data()!;
        expect(
          stored['blob'].toString().contains(b64(oldDev.identity.edPub)),
          isFalse,
        );

        final fresh = Phone(db, 'alice');
        await expectLater(
          fresh.keys.ensureDevice('alice'),
          throwsA(isA<NeedsRecoveryException>()),
        );
        final restored = await fresh.recovery.restoreWithRecoveryKey(
          'alice',
          (await rk.display()).toLowerCase(),
        );
        expect(restored.identity.publicBytes, oldDev.identity.publicBytes);
        expect(restored.keys.deviceId, isNot(oldDev.keys.deviceId));
        expect(await restored.bundle.verifyCert(), isTrue);
        expect(
          (await db.collection('users/alice/devices').get()).docs,
          hasLength(2),
        );
        // next launch just loads the keys
        expect(
          (await fresh.keys.ensureDevice('alice')).keys.deviceId,
          restored.keys.deviceId,
        );
      },
    );

    test(
      'wrong, mistyped, and missing keys are refused with clear errors',
      () async {
        final old = Phone(db, 'alice');
        final dev = await old.keys.ensureDevice('alice');
        final fresh = Phone(db, 'alice');
        await expectLater(
          fresh.recovery.restoreWithRecoveryKey('alice', 'ABCD'),
          throwsA(isA<RecoveryException>()),
        );
        final real = await old.recovery.createBackup('alice', dev.identity);
        final other = await RecoveryKey.generate().display();
        await expectLater(
          fresh.recovery.restoreWithRecoveryKey('alice', other),
          throwsA(isA<RecoveryException>()),
        );
        await expectLater(
          Phone(
            db,
            'bob',
          ).recovery.restoreWithRecoveryKey('bob', await real.display()),
          throwsA(isA<RecoveryException>()),
        );
      },
    );

    test(
      'resetIdentity starts over: new identity, old devices and backup gone',
      () async {
        final old = Phone(db, 'alice');
        final d = await old.keys.ensureDevice('alice');
        await old.recovery.createBackup('alice', d.identity);
        await db.collection('users/alice/pushTokens').doc(d.keys.deviceId).set({
          'token': 'example-token',
          'platform': 'android',
        });
        final fresh = Phone(db, 'alice');
        final reset = await fresh.recovery.resetIdentity('alice');
        expect(reset.identity.publicBytes, isNot(d.identity.publicBytes));
        // Alerts are no longer routed to the old devices.
        expect(
          (await db.collection('users/alice/pushTokens').get()).docs,
          isEmpty,
        );
        final docs = (await db.collection('users/alice/devices').get()).docs;
        expect(docs.map((x) => x.id), [reset.keys.deviceId]);
        expect(await fresh.recovery.hasBackup('alice'), isFalse);
        // a contact who pinned the old identity gets a warning
        final bob = Phone(db, 'bob');
        await bob.keys.ensureDevice('bob');
        await bob.keys.acceptIdentityChange('alice', d.identity.publicBytes);
        await expectLater(
          bob.keys.fetchDevices('alice'),
          throwsA(isA<IdentityChangedException>()),
        );
      },
    );
  });

  test('a device still running when its identity is replaced: the old '
      'device\'s certificate no longer passes for a contact who accepts the '
      'new identity', () async {
    final phone = Phone(db, 'alice');
    final before = await phone.keys.ensureDevice('alice');
    final stolen = before.bundle;
    final bob = Phone(db, 'bob');
    await bob.keys.ensureDevice('bob');
    expect(await bob.keys.fetchDevices('alice'), hasLength(1));

    final after = await phone.recovery.resetIdentity('alice');
    await expectLater(
      bob.keys.fetchDevices('alice'),
      throwsA(isA<IdentityChangedException>()),
    );
    await bob.keys.acceptIdentityChange('alice', after.identity.publicBytes);
    expect(
      (await bob.keys.fetchDevices('alice')).single.deviceId,
      after.keys.deviceId,
    );

    // Whoever holds the old device (and whoever serves records) puts its
    // record back. It is certified by the old identity, which Bob no longer
    // trusts, so it stays out.
    await db.collection('users/alice/devices').doc(stolen.deviceId).set({
      ...stolen.toFirestore(),
      'createdAt': DateTime(2026),
    });
    await expectLater(
      bob.keys.fetchDevices('alice'),
      throwsA(isA<IdentityChangedException>()),
    );
    await expectLater(
      bob.keys.fetchDevice('alice', stolen.deviceId),
      throwsA(isA<IdentityChangedException>()),
    );
  });

  group('device linking', () {
    late Phone existing, fresh;
    late LocalDevice existingDev;
    setUp(() async {
      existing = Phone(db, 'alice');
      existingDev = await existing.keys.ensureDevice('alice');
      fresh = Phone(db, 'alice');
    });

    test(
      'happy path: QR -> approve -> new device installed, nothing typed',
      () async {
        final req = await fresh.recovery.startLink('alice');
        expect(LinkQr.parse(req.qrPayload), isNotNull);
        await existing.recovery.approveLink(
          'alice',
          existingDev.identity,
          req.qrPayload,
        );
        final sealed = await fresh.recovery.awaitResponse(req);
        final dev = await fresh.recovery.completeLink(req, sealed);
        expect(dev.identity.publicBytes, existingDev.identity.publicBytes);
        expect(await dev.bundle.verifyCert(), isTrue);
        expect(
          (await db.collection('users/alice/devices').get()).docs,
          hasLength(2),
        );
        expect(
          (await db.collection('users/alice/linkRequests').get()).docs,
          isEmpty,
        );
        expect(
          (await fresh.keys.ensureDevice('alice')).keys.deviceId,
          req.keys.deviceId,
        );
      },
    );

    test(
      'a response made without the secret in the QR code does not open',
      () async {
        final req = await fresh.recovery.startLink('alice');
        // Someone who can write the response and knows every public value
        // picks an identity of their own. The new device cannot open what
        // was sealed without its secret.
        final evil = await AccountIdentity.generate();
        final forged = await LinkCrypto.seal(
          evil,
          uid: 'alice',
          deviceId: req.keys.deviceId,
          x25519Pub: req.keys.x25519Pub,
          kemPub: req.keys.kemPub,
          secret: Uint8List(16),
        );
        await expectLater(
          fresh.recovery.completeLink(req, forged),
          throwsA(isA<RecoveryException>()),
        );
        expect(await fresh.secrets.read('identity:alice'), isNull);
        expect(
          (await db.collection('users/alice/devices').get()).docs,
          hasLength(1),
        );
        // The request is still there, so the real answer can still arrive.
        await existing.recovery.approveLink(
          'alice',
          existingDev.identity,
          req.qrPayload,
        );
        final dev = await fresh.recovery.completeLink(
          req,
          await fresh.recovery.awaitResponse(req),
        );
        expect(dev.identity.publicBytes, existingDev.identity.publicBytes);
      },
    );

    test('the secret is in the QR code and not on the server', () async {
      final req = await fresh.recovery.startLink('alice');
      final qr = LinkQr.parse(req.qrPayload)!;
      expect(qr.secret, req.secret);
      expect(qr.secret, hasLength(16));
      final other = await fresh.recovery.startLink('alice');
      expect(other.secret, isNot(req.secret));
      final stored =
          (await db
                  .collection('users/alice/linkRequests')
                  .doc(req.keys.deviceId)
                  .get())
              .data()!
              .toString();
      expect(stored.contains(req.qrPayload.split('/').last), isFalse);
      expect(stored.contains(base64Encode(req.secret)), isFalse);
    });

    test('a QR code from an older version is refused in plain words', () async {
      final req = await fresh.recovery.startLink('alice');
      final qr = LinkQr.parse(req.qrPayload)!;
      await expectLater(
        existing.recovery.approveLink(
          'alice',
          existingDev.identity,
          'fireplace://link/1/alice/${qr.deviceId}/${qr.fingerprint}',
        ),
        throwsA(
          isA<RecoveryException>().having(
            (e) => e.message,
            'message',
            contains('Update Fireplace on the new device'),
          ),
        ),
      );
      final snap = await db
          .collection('users/alice/linkRequests')
          .doc(qr.deviceId)
          .get();
      expect(snap.data()!.containsKey('response'), isFalse);
    });

    test(
      'server swapping the new device keys is caught by the QR fingerprint',
      () async {
        final req = await fresh.recovery.startLink('alice');
        final evilKeys = await DeviceKeys.generate();
        await db
            .collection('users/alice/linkRequests')
            .doc(req.keys.deviceId)
            .update({
              'x25519Pub': b64(evilKeys.x25519Pub),
              'kemPub': b64(evilKeys.kemPub),
            });
        await expectLater(
          existing.recovery.approveLink(
            'alice',
            existingDev.identity,
            req.qrPayload,
          ),
          throwsA(isA<RecoveryException>()),
        );
      },
    );

    test(
      'junk QR, other account, expired and replayed requests are refused',
      () async {
        await expectLater(
          existing.recovery.approveLink(
            'alice',
            existingDev.identity,
            'https://x',
          ),
          throwsA(isA<RecoveryException>()),
        );
        final req = await fresh.recovery.startLink('alice');
        await expectLater(
          existing.recovery.approveLink(
            'bob',
            existingDev.identity,
            req.qrPayload,
          ),
          throwsA(isA<RecoveryException>()),
        );
        await existing.recovery.approveLink(
          'alice',
          existingDev.identity,
          req.qrPayload,
        );
        await expectLater(
          existing.recovery.approveLink(
            'alice',
            existingDev.identity,
            req.qrPayload,
          ),
          throwsA(isA<RecoveryException>()),
        );
        await fresh.recovery.cancelLink(req);
        await expectLater(
          existing.recovery.approveLink(
            'alice',
            existingDev.identity,
            req.qrPayload,
          ),
          throwsA(isA<RecoveryException>()),
        );
      },
    );

    test('linked device can chat with a contact', () async {
      final req = await fresh.recovery.startLink('alice');
      await existing.recovery.approveLink(
        'alice',
        existingDev.identity,
        req.qrPayload,
      );
      final dev = await fresh.recovery.completeLink(
        req,
        await fresh.recovery.awaitResponse(req),
      );
      await db.collection('usernames').doc('alice').set({'uid': 'alice'});
      await db.collection('usernames').doc('bob').set({'uid': 'bob'});
      await db.collection('users').doc('alice').set({'username': 'alice'});
      await db.collection('users').doc('bob').set({'username': 'bob'});
      final bob = Phone(db, 'bob');
      final bobDev = await bob.keys.ensureDevice('bob');
      final bobMsgs = MemoryMessageStore();
      await PreKeyService(db, bob.secrets).maintain('bob', bobDev);
      await PreKeyService(db, fresh.secrets).maintain('alice', dev);
      final bobChat = ChatService(
        db: db,
        uid: 'bob',
        device: bobDev,
        keys: bob.keys,
        prekeys: PreKeyService(db, bob.secrets),
        secrets: bob.secrets,
        messages: bobMsgs,
      );
      final chat = ChatService(
        db: db,
        uid: 'alice',
        device: dev,
        keys: fresh.keys,
        prekeys: PreKeyService(db, fresh.secrets),
        secrets: fresh.secrets,
        messages: MemoryMessageStore(),
      );
      final chatId = await chat.startChat('bob');
      final sub = bobChat.startSync(chatId);
      await chat.sendText(chatId, 'hello from the linked phone');
      for (var i = 0; i < 60; i++) {
        if ((await bobMsgs.watch(chatId).first).any(
          (m) => m.body == 'hello from the linked phone',
        )) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
      expect(
        (await bobMsgs.watch(chatId).first).map((m) => m.body),
        contains('hello from the linked phone'),
      );
      await sub.cancel();
    });
  });

  test('LinkQr parsing', () {
    final secret = Uint8List.fromList(List.generate(16, (i) => 255 - i * 3));
    final q = LinkQr('uid1', 'abcdefgh_-12', 'A' * 22, secret);
    final p = LinkQr.parse(q.encode())!;
    expect(
      [p.uid, p.deviceId, p.fingerprint],
      ['uid1', 'abcdefgh_-12', 'A' * 22],
    );
    expect(p.secret, secret);
    expect(q.encode(), startsWith('fireplace://link/2/uid1/abcdefgh_-12/'));
    final old = 'fireplace://link/1/uid1/abcdefgh_-12/${'A' * 22}';
    expect(LinkQr.isOld(old), isTrue);
    expect(LinkQr.isOld(q.encode()), isFalse);
    for (final j in [
      null,
      '',
      old,
      'fireplace://link/2/a/b/c',
      // No secret, a short one, a long one.
      'fireplace://link/2/uid1/abcdefgh_-12/${'A' * 22}',
      'fireplace://link/2/uid1/abcdefgh_-12/${'A' * 22}/${'A' * 21}',
      'fireplace://link/2/uid1/abcdefgh_-12/${'A' * 22}/${'A' * 23}',
      'fireplace://verify/1/${'1' * 60}',
    ]) {
      expect(LinkQr.parse(j), isNull);
    }
  });
}
