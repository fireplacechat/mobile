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

  /// Alice creates "Book club" and invites Bob, who joins.
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
    'create, invite, join: both see the same group, name and roles',
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
      expect(server.processed, containsAll(['create', 'invite', 'accept']));
      await until(
        () async => bob.service.invitations.isEmpty,
        what: 'the invitation goes',
      );
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
    final id = (await bob.messages.watch(groupChatId(gid)).first)
        .firstWhere((m) => m.body == 'only mine to hide')
        .id;
    await bob.service.deleteLocally(gid, id);
    expect(await texts(bob, gid), isNot(contains('only mine to hide')));
    expect(await texts(alice, gid), contains('only mine to hide'));
  });

  test(
    'any member invites, and the person joins from their invitation',
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
    // Invited: Bob's device is an MLS leaf, but not in the server's roster.
    expect(alice.service.groups[gid]!.members, hasLength(2));
    await bob.service.decline(gid);
    await until(() async => bob.service.invitations.isEmpty, what: 'declined');
    expect(bob.service.groups, isEmpty);
    // Alice's phone removes the leaf; nothing says Bob declined.
    await until(
      () async => alice.service.groups[gid]!.members.length == 1,
      what: 'the leaf removed',
    );
    expect(alice.service.invitedTo(gid), isEmpty);
    final lines = [
      for (final m in await alice.messages.watch(groupChatId(gid)).first)
        if (m.status == MessageStatus.notice) GroupNotice.decode(m.body)!.kind,
    ];
    expect(lines, [GroupNoticeKind.added, GroupNoticeKind.gone]);
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

  // ---------------------------------------------------------------- round 2

  /// The lines in a phone's history about changes to the group.
  Future<List<GroupNotice>> notices(Phone p, String gid) async => [
    for (final m in await p.messages.watch(groupChatId(gid)).first)
      if (m.status == MessageStatus.notice) GroupNotice.decode(m.body)!,
  ];
  Future<bool> hasNotice(
    Phone p,
    String gid,
    GroupNoticeKind kind, {
    String? by,
    String? who,
  }) async => (await notices(
    p,
    gid,
  )).any((n) => n.kind == kind && n.by == by && n.who == who);

  test('joining needs nobody else: the inviter can be offline', () async {
    final gid = await alice.service.create('Book club', ['bob']);
    await until(
      () async => bob.service.invitations.any((i) => i.gid == gid),
      what: 'invitation',
    );
    // The invitation already put Bob's device in the MLS group.
    expect(alice.service.invitedTo(gid), {'bob': 'alice'});
    await alice.service.send(gid, 'sent before Bob joined');
    await alice.service.close();

    await bob.service.accept(gid);
    // In the chat as soon as Join returns, with no other phone running.
    expect(bob.service.groups[gid]?.name, 'Book club');
    expect(server.processed, isNot(contains('add')));
    await until(
      () async =>
          ((await db.doc('groups/$gid').get()).data()!['members'] as Map)
              .containsKey('bob'),
      what: 'the roster',
    );
    await bob.service.send(gid, 'I am in');
    expect(await texts(bob, gid), contains('I am in'));
    // Nothing from before Bob joined is shown, and the screen can say so.
    expect(await texts(bob, gid), isNot(contains('sent before Bob joined')));
    expect(bob.service.joinedLater(gid), isTrue);
    alice = await Phone.create(FakeFirebaseFirestore(), 'alice2', root);
  });

  test('the person who made the group did not join later', () async {
    final gid = await bookClub();
    expect(alice.service.joinedLater(gid), isFalse);
    expect(bob.service.joinedLater(gid), isTrue);
  });

  test('someone with no key package left cannot be invited yet', () async {
    final gid = await alice.service.create('Book club', []);
    final devices = await db.collection('users/bob/devices').get();
    for (final p
        in (await devices.docs.first.reference.collection('mlsPackages').get())
            .docs) {
      await p.reference.delete();
    }
    await expectLater(
      alice.service.invite(gid, 'bob'),
      throwsA(
        isA<GroupRefused>().having((e) => e.reason, 'reason', 'packages'),
      ),
    );
    expect(alice.service.groups[gid]!.members, hasLength(1));
    expect(bob.service.invitations, isEmpty);
  });

  test(
    'an invitation nobody answers in seven days is ended by a member',
    () async {
      var now = DateTime.now();
      final carol = await Phone.create(db, 'carol', root, clock: () => now);
      server
        ..watchAccount('carol')
        ..now = () => now;
      final gid = await carol.service.create('Book club', ['bob']);
      await until(
        () async => bob.service.invitations.isNotEmpty,
        what: 'invitation',
      );
      now = now.add(const Duration(days: 8));
      // Any change to the group makes a member's phone look at it again.
      await carol.service.rename(gid, 'Tea club');
      await until(() async {
        final g = (await db.doc('groups/$gid').get()).data()!;
        return (g['invited'] as Map).isEmpty &&
            (g['fence'] as List).isEmpty &&
            carol.service.groups[gid]!.members.length == 1;
      }, what: 'expired and removed');
      await expectLater(
        bob.service.accept(gid),
        throwsA(anyOf(isA<GroupRefused>(), isA<GroupActionError>())),
      );
      expect(bob.service.groups, isEmpty);
      await carol.service.close();
    },
  );

  test('someone who joins later gets every member\'s colour', () async {
    alice.service.ownColor = 'plum';
    bob.service.ownColor = 'moss';
    final gid = await bookClub();
    final carol = await Phone.create(db, 'carol', root);
    carol.service.ownColor = 'sky';
    server.watchAccount('carol');
    await alice.service.invite(gid, 'carol');
    // More happens in the group before Carol answers.
    await alice.service.rename(gid, 'Tea club');
    await until(
      () async => carol.service.invitations.isNotEmpty,
      what: 'invitation',
    );
    await carol.service.accept(gid);
    await until(
      () async =>
          carol.service.colorsOf(gid)['alice'] == 'plum' &&
          carol.service.colorsOf(gid)['bob'] == 'moss',
      what: "Carol has both colours",
    );
    for (final p in [alice, bob]) {
      await until(
        () async => p.service.colorsOf(gid)['carol'] == 'sky',
        what: "Carol's colour on ${p.uid}",
      );
    }
    expect(carol.service.groups[gid]!.name, 'Tea club');
    await carol.service.close();
  });

  test("a phone that lacks a member's colour asks for it once", () async {
    alice.service.ownColor = 'plum';
    final gid = await bookClub();
    await until(
      () async => bob.service.colorsOf(gid)['alice'] == 'plum',
      what: 'the colour',
    );
    // Bob's phone as it was before members answered a newcomer: it joined, and
    // nobody's colour ever arrived.
    await bob.service.close();
    await bob.secrets.delete('groupcolors:bob');
    final again = GroupService(
      db: db,
      uid: 'bob',
      device: await KeyService(db, bob.secrets).ensureDevice('bob'),
      secrets: bob.secrets,
      historyDir: Directory('${root.path}/bob'),
      messages: bob.messages,
      colourCatchUp: const Duration(milliseconds: 100),
    );
    await again.start();
    expect(again.colorsOf(gid), isEmpty);
    await until(
      () async => again.colorsOf(gid)['alice'] == 'plum',
      what: 'the colour, asked for',
    );
    await again.close();
    bob = await Phone.create(FakeFirebaseFirestore(), 'bob2', root);
  });

  test('changes to the group are written into the history as lines', () async {
    final gid = await bookClub();
    for (final p in [alice, bob]) {
      // Bob's own phone joined at the epoch after the Add, so only Alice's
      // has the line for it.
      if (p == alice) {
        expect(
          await hasNotice(
            p,
            gid,
            GroupNoticeKind.added,
            by: 'alice',
            who: 'bob',
          ),
          isTrue,
        );
      }
    }
    await alice.service.rename(gid, 'Tea club');
    await alice.service.setAdmin(gid, 'bob', admin: true);
    for (final p in [alice, bob]) {
      await until(
        () async =>
            await hasNotice(p, gid, GroupNoticeKind.renamed, by: 'alice') &&
            await hasNotice(
              p,
              gid,
              GroupNoticeKind.madeAdmin,
              by: 'alice',
              who: 'bob',
            ),
        what: 'rename and role lines on ${p.uid}',
      );
    }
    await bob.service.setAdmin(gid, 'alice', admin: false);
    await until(
      () async => await hasNotice(
        alice,
        gid,
        GroupNoticeKind.removedAdmin,
        by: 'bob',
        who: 'alice',
      ),
      what: 'the role line',
    );
    // Lines are not messages: they never count as text from a person.
    final line = (await alice.messages.watch(groupChatId(gid)).first)
        .firstWhere((m) => m.status == MessageStatus.notice);
    expect(GroupNotice.decode(line.body), isNotNull);
    expect(
      const GroupNotice(
        GroupNoticeKind.added,
        by: 'alice',
        who: 'bob',
      ).text((uid) => uid == 'alice' ? 'You' : uid),
      'You added bob',
    );
  });

  test('a line says whether someone left or was removed', () async {
    final gid = await bookClub();
    final carol = await Phone.create(db, 'carol', root);
    server.watchAccount('carol');
    await alice.service.invite(gid, 'carol');
    await until(
      () async => carol.service.invitations.isNotEmpty,
      what: 'invitation',
    );
    await carol.service.accept(gid);
    await until(
      () async => alice.service.groups[gid]!.members.length == 3,
      what: 'three people',
    );
    await carol.service.leave(gid);
    await until(
      () async =>
          await hasNotice(alice, gid, GroupNoticeKind.left, who: 'carol'),
      what: 'Carol left',
    );
    await alice.service.remove(gid, 'bob');
    await until(
      () async => await hasNotice(
        alice,
        gid,
        GroupNoticeKind.removed,
        by: 'alice',
        who: 'bob',
      ),
      what: 'Bob removed',
    );
    await carol.service.close();
  });

  test('an administrator makes another; a member cannot', () async {
    final gid = await bookClub();
    await expectLater(
      bob.service.setAdmin(gid, 'bob', admin: true),
      throwsA(isA<GroupActionError>()),
    );
    await alice.service.setAdmin(gid, 'bob', admin: true);
    for (final p in [alice, bob]) {
      await until(
        () async => p.service.groups[gid]!.isAdmin('bob'),
        what: 'Bob administers on ${p.uid}',
      );
    }
    expect(
      ((await db.doc('groups/$gid').get()).data()!['members']
          as Map)['bob']['role'],
      'admin',
    );
    // The last administrator cannot stop being one.
    await bob.service.setAdmin(gid, 'alice', admin: false);
    await until(
      () async => !bob.service.groups[gid]!.isAdmin('alice'),
      what: 'Alice no longer administers',
    );
    await expectLater(
      bob.service.setAdmin(gid, 'bob', admin: false),
      throwsA(isA<GroupActionError>()),
    );
  });

  test("a member's role change is refused by the others", () async {
    final gid = await bookClub();
    final epoch = alice.service.groups[gid]!.epoch;
    // Bob's phone is made to send what the app never would.
    await bob.service.commitMetaUnchecked(gid, admins: ['bob']);
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(alice.service.groups[gid]!.isAdmin('bob'), isFalse);
    expect(alice.service.groups[gid]!.isAdmin('alice'), isTrue);
    expect(alice.service.groups[gid]!.epoch, epoch);
    expect(
      await notices(alice, gid),
      everyElement(
        isA<GroupNotice>().having((n) => n.kind, 'kind', GroupNoticeKind.added),
      ),
    );
  });

  test('an invited person who is removed never joins', () async {
    final gid = await alice.service.create('Book club', ['bob']);
    await until(
      () async => bob.service.invitations.isNotEmpty,
      what: 'invitation',
    );
    await alice.service.remove(gid, 'bob');
    await until(() async => bob.service.invitations.isEmpty, what: 'withdrawn');
    expect(alice.service.groups[gid]!.members, hasLength(1));
    expect(alice.service.invitedTo(gid), isEmpty);
  });
}
