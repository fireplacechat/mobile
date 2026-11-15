// Who a group member is (decision 0061): the identity key in every member's
// credential is compared with the key this phone trusts for that account. The
// real Rust MLS core, a fake Firestore, and a fake of the request function.
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_crypto.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/crypto/group_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_group_server.dart';
import '../../support/group_phones.dart';

void main() {
  late Directory root;
  late FakeFirebaseFirestore db;
  late FakeGroupServer server;
  late Phone alice, bob, carol;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('group-identity');
    db = FakeFirebaseFirestore();
    server = FakeGroupServer(db);
    alice = await Phone.create(db, 'alice', root);
    bob = await Phone.create(db, 'bob', root);
    carol = await Phone.create(db, 'carol', root);
    for (final p in [alice, bob, carol]) {
      server.watchAccount(p.uid);
    }
  });
  tearDown(() async {
    for (final p in [alice, bob, carol]) {
      await p.service.close();
    }
    await server.close();
    await root.delete(recursive: true);
  });

  Future<void> join(Phone p, String gid) async {
    await until(
      () async => p.service.invitations.any((i) => i.gid == gid),
      what: 'invitation for ${p.uid}',
    );
    await p.service.accept(gid);
    await until(
      () async => p.service.groups.containsKey(gid),
      what: '${p.uid} joins',
    );
  }

  Future<List<int>> identityOf(Phone p) async =>
      (await p.keys.ensureDevice(p.uid)).identity.publicBytes;

  /// An identity key that belongs to nobody in the test.
  Future<List<int>> strangerIdentity() async =>
      (await AccountIdentity.generate()).publicBytes;

  Future<int> commits(String gid) async =>
      (await db.collection('groups/$gid/commits').get()).docs.length;

  test('an invitation remembers the invited person as a chat with them would, '
      'and every member remembers the others on first sight', () async {
    expect(await alice.keys.pinnedIdentity('bob'), isNull);
    final gid = await alice.service.create('Book club', ['bob']);
    await join(bob, gid);
    expect(await alice.keys.pinnedIdentity('bob'), await identityOf(bob));
    expect(await bob.keys.pinnedIdentity('alice'), await identityOf(alice));

    // Bob has never talked to Carol. He learns her key from Alice's Commit,
    // which MLS authenticated, and keeps it.
    expect(await bob.keys.pinnedIdentity('carol'), isNull);
    await alice.service.invite(gid, 'carol');
    await until(
      () async => bob.service.groups[gid]!.members.length == 3,
      what: 'Bob sees Carol',
    );
    expect(await bob.keys.pinnedIdentity('carol'), await identityOf(carol));
    expect(bob.service.heldChanges, isEmpty);
    await join(carol, gid);
    expect(await carol.keys.pinnedIdentity('bob'), await identityOf(bob));
  });

  test('a key package made under another identity in the invited person\'s '
      'name is refused before anything is sent', () async {
    final gid = await alice.service.create('Book club', []);
    // Whoever serves key packages answers with one of its own: a credential
    // that names Bob and his device, signed by an identity it made itself.
    final device = (await db.collection('users/bob/devices').get()).docs.single;
    final forger = GroupCrypto.open(const []);
    forger.call({
      'op': 'device',
      'identity': jsonEncode((await AccountIdentity.generate()).toJson()),
      'uid': 'bob',
      'device': device.id,
      'deviceCertHash': base64Encode(
        (await Sha256().hash(
          base64Decode(device.data()['deviceCert'] as String),
        )).bytes,
      ),
      'generation': 1,
    });
    forger.accept();
    final made = forger.call({'op': 'key_packages', 'count': 1});
    final forged = base64Decode(
      ((made['packages'] as List).single as Map)['keyPackage'] as String,
    );
    final slots = await device.reference.collection('mlsPackages').get();
    for (final slot in slots.docs) {
      await slot.reference.update({'kp': Blob(forged)});
    }

    final before = await commits(gid);
    final epoch = alice.service.groups[gid]!.epoch;
    await expectLater(alice.service.invite(gid, 'bob'), throwsA(anything));
    expect(await commits(gid), before);
    expect(alice.service.groups[gid]!.epoch, epoch);
    expect(alice.service.groups[gid]!.members.map((m) => m.uid), ['alice']);
    expect((await db.collection('groups/$gid/welcomes').get()).docs, isEmpty);
    expect(server.processed, isNot(contains('invite')));
    // The key Alice trusts for Bob is still his.
    expect(await alice.keys.pinnedIdentity('bob'), await identityOf(bob));
  });

  test(
    'a Commit that adds someone under a key this phone does not trust for them '
    'stops the group here until the person accepts the key',
    () async {
      final gid = await alice.service.create('Book club', ['bob']);
      await join(bob, gid);
      // Bob knows Carol under another key (as after she reset her account,
      // or when somebody stands in for her).
      await bob.keys.acceptIdentityChange('carol', await strangerIdentity());
      final epoch = bob.service.groups[gid]!.epoch;

      await alice.service.invite(gid, 'carol');
      await until(
        () async => bob.service.heldChanges.containsKey(gid),
        what: 'Bob holds the change',
      );
      final held = bob.service.heldChanges[gid]!;
      expect(held.peerUid, 'carol');
      expect(held.newIdentityPub, await identityOf(carol));
      expect(bob.service.groups[gid]!.epoch, epoch);
      expect(bob.service.groups[gid]!.members.map((m) => m.uid).toSet(), {
        'alice',
        'bob',
      });

      // Trying again without accepting changes nothing.
      await bob.service.retryHeld();
      expect(bob.service.groups[gid]!.epoch, epoch);
      expect(bob.service.heldChanges.containsKey(gid), isTrue);

      // Nothing newer is read while the group is held.
      await join(carol, gid);
      await alice.service.send(gid, 'welcome, carol');
      await until(
        () async => (await texts(carol, gid)).contains('welcome, carol'),
        what: 'Carol receives',
      );
      expect(await texts(bob, gid), isNot(contains('welcome, carol')));

      // The person looks at the new key and accepts it.
      await bob.keys.acceptIdentityChange('carol', held.newIdentityPub);
      await bob.service.retryHeld();
      await until(
        () async => bob.service.groups[gid]!.members.length == 3,
        what: 'Bob sees Carol',
      );
      expect(bob.service.heldChanges, isEmpty);
      await until(
        () async => (await texts(bob, gid)).contains('welcome, carol'),
        what: 'Bob catches up',
      );
    },
  );

  test('joining waits when a member\'s key is not the one this phone trusts, '
      'and nothing of the group is kept until then', () async {
    final gid = await alice.service.create('Book club', ['bob']);
    await until(
      () async => bob.service.invitations.any((i) => i.gid == gid),
      what: 'invitation',
    );
    await bob.keys.acceptIdentityChange('alice', await strangerIdentity());

    await expectLater(
      bob.service.accept(gid),
      throwsA(
        isA<IdentityChangedException>().having(
          (e) => e.peerUid,
          'who',
          'alice',
        ),
      ),
    );
    expect(bob.service.groups, isEmpty);
    expect(bob.service.heldChanges[gid]!.peerUid, 'alice');
    expect(server.processed, isNot(contains('accept')));

    await bob.keys.acceptIdentityChange('alice', await identityOf(alice));
    await bob.service.accept(gid);
    await until(
      () async => bob.service.groups.containsKey(gid),
      what: 'Bob joins',
    );
    expect(bob.service.heldChanges, isEmpty);
  });

  test('an invitation for someone whose key changed is not sent', () async {
    final gid = await alice.service.create('Book club', []);
    await alice.keys.acceptIdentityChange('bob', await strangerIdentity());
    final before = await commits(gid);
    await expectLater(
      alice.service.invite(gid, 'bob'),
      throwsA(isA<IdentityChangedException>()),
    );
    expect(await commits(gid), before);
    expect(server.processed, isNot(contains('invite')));
  });
}
