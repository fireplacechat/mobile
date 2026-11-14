// Group chats end to end on two devices (decision 0050): the real Rust MLS core,
// a fake Firestore, and a fake of the backend's request function.
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/model/groups/group_models.dart';
import 'package:fireplace/src/model/groups/group_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_group_server.dart';
import '../../support/group_phones.dart';

void main() {
  late Directory root;
  late FakeFirebaseFirestore db;
  late FakeGroupServer server;
  late Phone alice, bob;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('groups');
    db = FakeFirebaseFirestore();
    server = FakeGroupServer(db);
    alice = await Phone.create(db, 'alice', root);
    bob = await Phone.create(db, 'bob', root);
    server
      ..watchAccount('alice')
      ..watchAccount('bob');
  });
  tearDown(() async {
    await alice.service.close();
    await bob.service.close();
    await server.close();
    await root.delete(recursive: true);
  });

  /// Alice creates "Book club" and invites Bob, who accepts and is added.
  Future<String> bookClub() async {
    final gid = await alice.service.create('Book club', ['bob']);
    await until(
      () async => bob.service.invitations.any((i) => i.gid == gid),
      what: 'invitation',
    );
    await bob.service.accept(gid);
    await until(
      () async => bob.service.groups.containsKey(gid),
      what: 'Bob joins',
    );
    await until(
      () async => alice.service.groups[gid]!.members.length == 2,
      what: 'Alice sees Bob',
    );
    return gid;
  }

  test('a device publishes ten key packages when it starts', () async {
    final devices = await db.collection('users/bob/devices').get();
    final packages = await db
        .collection('users/bob/devices/${devices.docs.first.id}/mlsPackages')
        .get();
    expect(packages.docs, hasLength(GroupLimits.keyPackagesPerDevice));
  });

  test(
    'create, invite, accept: both see the same group, name and roles',
    () async {
      final gid = await bookClub();
      for (final p in [alice, bob]) {
        final info = p.service.groups[gid]!;
        expect(info.name, 'Book club');
        expect(info.members.map((m) => m.uid).toSet(), {'alice', 'bob'});
        expect(info.isAdmin('alice'), isTrue);
        expect(info.isAdmin('bob'), isFalse);
      }
      expect(alice.service.groups[gid]!.epoch, bob.service.groups[gid]!.epoch);
      expect(
        server.processed,
        containsAll(['create', 'invite', 'accept', 'add']),
      );
      // Bob's used key package is gone from the server.
      expect(bob.service.invitations, isEmpty);
    },
  );

  test(
    'messages reach the other member, never twice, with the right sender',
    () async {
      final gid = await bookClub();
      await alice.service.send(gid, 'Anyone bringing snacks?');
      await until(
        () async => (await texts(bob, gid)).contains('Anyone bringing snacks?'),
        what: 'Bob receives',
      );
      await bob.service.send(gid, 'I can do chips');
      await until(
        () async => (await texts(alice, gid)).contains('I can do chips'),
        what: 'Alice receives',
      );
      final bobs = await bob.messages.watch(groupChatId(gid)).first;
      final fromAlice = bobs.firstWhere(
        (m) => m.body == 'Anyone bringing snacks?',
      );
      expect(fromAlice.senderUid, 'alice');
      expect(fromAlice.outgoing, isFalse);
      final own = bobs.firstWhere((m) => m.body == 'I can do chips');
      expect(own.outgoing, isTrue);
      expect(own.status, MessageStatus.ok);
      expect(
        (await texts(alice, gid)).where((t) => t == 'I can do chips'),
        hasLength(1),
      );
    },
  );

  test('members share their colour inside the group', () async {
    alice.service.ownColor = 'plum';
    final gid = await bookClub();
    await alice.service.shareColor();
    await until(
      () async => bob.service.colorsOf(gid)['alice'] == 'plum',
      what: 'colour',
    );
    await until(
      () async => alice.service.colorsOf(gid)['bob'] == 'ember',
      what: "Bob's colour",
    );
  });

  test('an administrator renames the group for everyone', () async {
    final gid = await bookClub();
    await alice.service.rename(gid, 'Tea club');
    for (final p in [alice, bob]) {
      await until(
        () async => p.service.groups[gid]?.name == 'Tea club',
        what: 'rename on ${p.uid}',
      );
    }
  });

  test("a member's rename is refused by the others", () async {
    final gid = await bookClub();
    final epoch = alice.service.groups[gid]!.epoch;
    await bob.service.rename(gid, 'Bob club');
    // Bob's Commit took the slot, but Alice will not apply it.
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(alice.service.groups[gid]!.name, 'Book club');
    expect(alice.service.groups[gid]!.epoch, epoch);
  });

  test(
    'leaving stops the group for the leaver and a member finalises it',
    () async {
      final gid = await bookClub();
      final epoch = alice.service.groups[gid]!.epoch;
      await bob.service.leave(gid);
      expect(bob.service.groups.containsKey(gid), isFalse);
      await until(
        () async =>
            (await db.doc('groups/$gid').get()).data()!['fence'].isEmpty &&
            alice.service.groups[gid]!.epoch == epoch + 1,
        what: 'finalised',
      );
      expect(alice.service.groups[gid]!.members.map((m) => m.uid), ['alice']);
      // Alice keeps chatting in the (now one-person) group.
      await alice.service.send(gid, 'still here');
    },
  );

  test(
    'only the author edits or deletes for everyone; anyone reacts',
    () async {
      final gid = await bookClub();
      await alice.service.send(gid, 'See you at 7');
      Future<LocalMessage?> bobsCopy() async =>
          (await bob.messages.watch(groupChatId(gid)).first)
              .where((m) => m.senderUid == 'alice' && m.visible)
              .firstOrNull;
      await until(() async => (await bobsCopy()) != null, what: 'delivered');
      final id = (await bobsCopy())!.id;

      await alice.service.edit(gid, id, 'See you at 8');
      await until(
        () async => (await bobsCopy())?.body == 'See you at 8',
        what: 'edit',
      );
      // Bob cannot edit or delete Alice's message.
      await expectLater(
        bob.service.edit(gid, id, 'hacked'),
        throwsA(isA<GroupActionError>()),
      );
      await expectLater(
        bob.service.deleteForEveryone(gid, id),
        throwsA(isA<GroupActionError>()),
      );

      await bob.service.react(gid, id, '👍');
      await until(
        () async =>
            (await alice.messages.get(
              groupChatId(gid),
              id,
            ))?.reactions['bob']?.emoji ==
            '👍',
        what: 'reaction',
      );

      await alice.service.deleteForEveryone(gid, id);
      await until(
        () async =>
            (await bob.messages.get(groupChatId(gid), id))?.remotelyDeleted ==
            true,
        what: 'deleted for everyone',
      );
    },
  );

  test('a member deletes a message from their own phone only', () async {
    final gid = await bookClub();
    await alice.service.send(gid, 'only mine to hide');
    await until(
      () async => (await texts(bob, gid)).contains('only mine to hide'),
      what: 'delivered',
    );
    final id = (await bob.messages.watch(groupChatId(gid)).first).first.id;
    await bob.service.deleteLocally(gid, id);
    expect(await texts(bob, gid), isNot(contains('only mine to hide')));
    expect(await texts(alice, gid), contains('only mine to hide'));
  });

  test(
    'any member invites, and their device adds the person who accepts',
    () async {
      final gid = await bookClub();
      final carol = await Phone.create(db, 'carol', root);
      server.watchAccount('carol');
      await bob.service.invite(gid, 'carol');
      await until(
        () async => carol.service.invitations.isNotEmpty,
        what: 'invitation',
      );
      await carol.service.accept(gid);
      await until(
        () async => carol.service.groups.containsKey(gid),
        what: 'Carol joins',
      );
      await until(
        () async => alice.service.groups[gid]!.members.length == 3,
        what: 'Alice sees Carol',
      );
      await carol.service.send(gid, 'hello from Carol');
      await until(
        () async => (await texts(alice, gid)).contains('hello from Carol'),
        what: 'Carol speaks',
      );
      await carol.service.close();
    },
  );

  test('the group ends when its last member leaves', () async {
    final gid = await bookClub();
    await bob.service.leave(gid);
    await alice.service.leave(gid);
    expect(alice.service.groups, isEmpty);
    await until(
      () async => !(await db.doc('groups/$gid').get()).exists,
      what: 'group deleted',
    );
  });

  test('a declined invitation goes away and adds nobody', () async {
    final gid = await alice.service.create('Book club', ['bob']);
    await until(
      () async => bob.service.invitations.isNotEmpty,
      what: 'invitation',
    );
    await bob.service.decline(gid);
    await until(() async => bob.service.invitations.isEmpty, what: 'declined');
    expect(bob.service.groups, isEmpty);
    expect(alice.service.groups[gid]!.members, hasLength(1));
  });

  test('a device restarted from its saved records carries on', () async {
    final gid = await bookClub();
    await bob.service.close();
    final devices = await db.collection('users/bob/devices').get();
    final device = await KeyService(db, bob.secrets).ensureDevice('bob');
    expect(device.keys.deviceId, devices.docs.first.id);
    final again = GroupService(
      db: db,
      uid: 'bob',
      device: device,
      secrets: bob.secrets,
      historyDir: Directory('${root.path}/bob'),
      messages: bob.messages,
    );
    await again.start();
    expect(again.groups[gid]!.name, 'Book club');
    await alice.service.send(gid, 'after a restart');
    await until(
      () async => (await texts(bob, gid)).contains('after a restart'),
      what: 'after restart',
    );
    await again.close();
    bob = await Phone.create(
      FakeFirebaseFirestore(),
      'bob2',
      root,
    ); // for tearDown
  });
}
