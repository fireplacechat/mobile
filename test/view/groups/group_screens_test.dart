// Group screens over real group services (decision 0050): the signed-in
// account is Alice, as in UiFixture; Bob is a second phone.
import 'dart:async';
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/src/app/group_providers.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat_list/chat_list_screen.dart';
import 'package:fireplace/src/view/groups/group_chat_screen.dart';
import 'package:fireplace/src/view/groups/group_info_screen.dart';
import 'package:fireplace/src/view/groups/new_group_screen.dart';
import 'package:fireplace/src/view/safety/requests_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_group_server.dart';
import '../../support/group_phones.dart';
import '../../support/ui_fixture.dart';

void main() {
  late Directory root;
  late FakeFirebaseFirestore db;
  late FakeGroupServer server;
  late Phone alice, bob;

  Future<void> setUpPhones(WidgetTester t) => t.runAsync(() async {
    root = await Directory.systemTemp.createTemp('group_screens');
    db = FakeFirebaseFirestore();
    server = FakeGroupServer(db);
    alice = await Phone.create(db, 'alice', root);
    bob = await Phone.create(db, 'bob', root);
    server
      ..watchAccount('alice')
      ..watchAccount('bob');
  });

  /// Closes the phones while both event loops run: a close can wait on work
  /// a screen started under the test's fake clock.
  Future<void> tearDownPhones(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    var closed = false;
    unawaited(
      Future.wait([alice.service.close(), bob.service.close(), server.close()])
          .whenComplete(() => closed = true),
    );
    for (var i = 0; i < 200 && !closed; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await t.pump(const Duration(milliseconds: 25));
    }
    expect(closed, isTrue);
    await t.runAsync(() => root.delete(recursive: true));
  }

  /// [admin] creates "Book club" and invites [member], who joins.
  Future<String> bookClub(WidgetTester t, Phone admin, Phone member) async =>
      (await t.runAsync(() async {
        final gid = await admin.service.create('Book club', [member.uid]);
        await until(
          () async => member.service.invitations.any((i) => i.gid == gid),
          what: 'invitation',
        );
        await member.service.accept(gid);
        await until(
          () async => admin.service.groups[gid]!.members.length == 2,
          what: 'joined',
        );
        return gid;
      }))!;

  /// Lets both the real event loop (MLS, fake server) and the test's fake
  /// clock run until [done] holds.
  Future<void> settle(WidgetTester t, bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await t.pump(const Duration(milliseconds: 25));
    }
    expect(done(), isTrue);
  }

  Future<UiFixture> pump(WidgetTester t, Widget home) async {
    final f = UiFixture();
    await f.seed();
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          ...f.overrides,
          groupServiceProvider.overrideWithValue(alice.service),
          groupContactsProvider.overrideWithValue(const ['bob', 'fred']),
        ],
        child: MaterialApp(theme: fireplaceTheme(Brightness.light), home: home),
      ),
    );
    // Let the providers' first values arrive from the real event loop.
    for (var i = 0; i < 8; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await t.pump(const Duration(milliseconds: 25));
    }
    return f;
  }

  testWidgets('the chat list shows a group with who wrote the last message', (
    t,
  ) async {
    await setUpPhones(t);
    final gid = await bookClub(t, alice, bob);
    await t.runAsync(() => bob.service.send(gid, 'See you at 7?'));
    await pump(t, const ChatListScreen());
    await settle(
      t,
      () => find.text('bob: See you at 7?').evaluate().isNotEmpty,
    );
    expect(find.text('Book club'), findsOneWidget);
    await tearDownPhones(t);
  });

  testWidgets('New chat offers a group; Create needs a name and a person', (
    t,
  ) async {
    await setUpPhones(t);
    await pump(t, const ChatListScreen());
    await t.tap(find.byKey(const Key('newChat')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('peerUsername')), findsOneWidget);
    await t.tap(find.byKey(const Key('newGroup')));
    await t.pumpAndSettle();
    expect(find.byType(NewGroupScreen), findsOneWidget);
    Widget create() =>
        t.widget<TextButton>(find.byKey(const Key('createGroup')));
    expect((create() as TextButton).onPressed, isNull);
    await t.enterText(find.byKey(const Key('groupName')), 'Book club');
    await t.pump();
    expect((create() as TextButton).onPressed, isNull);
    await t.tap(find.byKey(const Key('pick_bob')));
    await t.pump();
    expect((create() as TextButton).onPressed, isNotNull);
    await t.tap(find.byKey(const Key('createGroup')));
    await settle(t, () => find.byType(GroupChatScreen).evaluate().isNotEmpty);
    expect(alice.service.groups.values.single.name, 'Book club');
    await settle(t, () => bob.service.invitations.isNotEmpty);
    await tearDownPhones(t);
  });

  testWidgets("names and avatars mark others' messages; only your own "
      'can be deleted for everyone', (t) async {
    await setUpPhones(t);
    final gid = await bookClub(t, alice, bob);
    await t.runAsync(() async {
      await bob.service.send(gid, 'from Bob');
      await until(
        () async => (await texts(alice, gid)).contains('from Bob'),
        what: 'delivered',
      );
      await alice.service.send(gid, 'from Alice');
    });
    await pump(t, GroupChatScreen(gid: gid));
    await settle(t, () => find.text('from Alice').evaluate().isNotEmpty);
    expect(find.text('bob'), findsOneWidget); // the name above Bob's run
    expect(find.text('2 people'), findsOneWidget);

    await t.longPress(find.text('from Bob'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('deleteForEveryone')), findsNothing);
    expect(find.byKey(const Key('editGroupMessage')), findsNothing);
    expect(find.byKey(const Key('deleteForMe')), findsOneWidget);
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();

    await t.longPress(find.text('from Alice'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('deleteForEveryone')), findsOneWidget);
    await t.tap(find.byKey(const Key('deleteForEveryone')));
    await settle(t, () => find.text('from Alice').evaluate().isEmpty);
    await t.runAsync(
      () => until(
        () async =>
            !(await texts(bob, gid)).contains('from Alice') ||
            (await bob.messages.watch('group-$gid').first).any(
              (m) => m.body == 'from Alice' && m.remotelyDeleted,
            ),
        what: 'deleted for Bob',
      ),
    );
    await tearDownPhones(t);
  });

  testWidgets('an administrator sees rename and remove; a member does not', (
    t,
  ) async {
    await setUpPhones(t);
    final mine = await bookClub(t, alice, bob);
    final theirs = await bookClub(t, bob, alice);
    await pump(t, GroupInfoScreen(gid: mine));
    expect(find.byKey(const Key('renameGroup')), findsOneWidget);
    expect(find.byKey(const Key('remove_bob')), findsOneWidget);
    expect(find.byKey(const Key('addPeople')), findsOneWidget);
    expect(find.text('Administrator'), findsOneWidget);

    await pump(t, GroupInfoScreen(gid: theirs));
    expect(find.byKey(const Key('renameGroup')), findsNothing);
    expect(find.byKey(const Key('remove_bob')), findsNothing);
    // Any member may invite people they chat with.
    expect(find.byKey(const Key('addPeople')), findsOneWidget);
    await tearDownPhones(t);
  });

  testWidgets('an invitation waits in Message requests until you join', (
    t,
  ) async {
    await setUpPhones(t);
    final gid = (await t.runAsync(() async {
      final gid = await bob.service.create('Tea club', ['alice']);
      await until(() async => alice.service.invitations.isNotEmpty);
      return gid;
    }))!;
    await pump(t, const RequestsScreen());
    expect(find.text('@bob invited you to a group'), findsOneWidget);
    await t.tap(find.byKey(const Key('joinGroup')));
    await settle(t, () => alice.service.groups.containsKey(gid));
    await settle(
      t,
      () => find.byKey(Key('groupInvite_$gid')).evaluate().isEmpty,
    );
    expect(alice.service.groups[gid]!.name, 'Tea club');
    await tearDownPhones(t);
  });
}
