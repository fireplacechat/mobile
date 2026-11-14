// Group screens over real group services (decision 0050): the signed-in
// account is Alice, as in UiFixture; Bob is a second phone.
import 'dart:async';
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/src/app/chat_color_preference.dart';
import 'package:fireplace/src/app/group_providers.dart';
import 'package:fireplace/src/styles/chat_colors.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat/widgets/message_quote_preview.dart';
import 'package:fireplace/src/view/chat_list/chat_list_screen.dart';
import 'package:fireplace/src/view/groups/group_chat_screen.dart';
import 'package:fireplace/src/view/groups/group_info_screen.dart';
import 'package:fireplace/src/view/groups/new_group_screen.dart';
import 'package:fireplace/src/view/safety/requests_screen.dart';
import 'package:fireplace/src/widgets/avatar.dart';
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

  /// A control in the held-message menu, the same one 1:1 chats use.
  Finder action(String id) => find.byKey(ValueKey('messageAction-$id'));

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

    // The same held-message menu as a 1:1 chat.
    await t.longPress(find.text('from Bob'));
    await t.pumpAndSettle();
    expect(action('deleteForEveryone'), findsNothing);
    expect(action('edit'), findsNothing);
    expect(action('deleteForMe'), findsOneWidget);
    expect(action('react-👍'), findsOneWidget);
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();

    await t.longPress(find.text('from Alice'));
    await t.pumpAndSettle();
    expect(action('edit'), findsOneWidget);
    await t.tap(action('deleteForEveryone'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('confirmRemoteDelete')));
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

  testWidgets('editing your message happens in the composer, as in a 1:1 '
      'chat', (t) async {
    await setUpPhones(t);
    final gid = await bookClub(t, alice, bob);
    await t.runAsync(() => alice.service.send(gid, 'See you at 7'));
    await pump(t, GroupChatScreen(gid: gid));
    await settle(t, () => find.text('See you at 7').evaluate().isNotEmpty);
    await t.longPress(find.text('See you at 7'));
    await t.pumpAndSettle();
    await t.tap(action('edit'));
    await t.pumpAndSettle();
    // No dialog: the composer holds the text, under an "Edit message" bar.
    expect(find.byType(Dialog), findsNothing);
    expect(find.byKey(const Key('editComposerPreview')), findsOneWidget);
    final composer = find.byKey(const Key('composer'));
    expect(t.widget<TextField>(composer).controller!.text, 'See you at 7');
    // Nothing to save until the text changes.
    expect(
      t.widget<IconButton>(find.byKey(const Key('send'))).onPressed,
      isNull,
    );
    await t.enterText(composer, 'See you at 8');
    await t.pump();
    await t.tap(find.byKey(const Key('send')));
    await settle(
      t,
      () =>
          find.byKey(const Key('editComposerPreview')).evaluate().isEmpty &&
          find.text('See you at 8').evaluate().isNotEmpty,
    );
    expect(t.widget<TextField>(composer).controller!.text, isEmpty);
    expect(t.takeException(), isNull);
    await t.runAsync(
      () => until(
        () async => (await texts(bob, gid)).contains('See you at 8'),
        what: 'the edit reaches Bob',
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
    // Join goes straight into the conversation.
    await settle(t, () => find.byType(GroupChatScreen).evaluate().isNotEmpty);
    expect(find.text('Tea club'), findsOneWidget);
    await tearDownPhones(t);
  });

  // ------------------------------------------- colours, lines, unread, mute, roles

  testWidgets("others' messages use the soft tint of their own colour; "
      'names and avatars use its text shade', (t) async {
    await setUpPhones(t);
    bob.service.ownColor = 'plum';
    final gid = await bookClub(t, alice, bob);
    await t.runAsync(() async {
      await bob.service.send(gid, 'from Bob');
      await until(
        () async =>
            (await texts(alice, gid)).contains('from Bob') &&
            alice.service.colorsOf(gid)['bob'] == 'plum',
        what: 'the message and the colour',
      );
      await alice.service.send(gid, 'from Alice');
    });
    await pump(t, GroupChatScreen(gid: gid));
    await settle(t, () => find.text('from Alice').evaluate().isNotEmpty);
    final history = (await t.runAsync(
      () => alice.messages.watch('group-$gid').first,
    ))!;
    String idOf(String body) => history.firstWhere((m) => m.body == body).id;
    Color fill(String body) =>
        (t
                    .widget<Container>(
                      find.byKey(ValueKey('messageBubble-${idOf(body)}')),
                    )
                    .decoration!
                as BoxDecoration)
            .color!;
    expect(fill('from Bob'), ChatBubbleColor.plum.incoming(Brightness.light));
    final own = ProviderScope.containerOf(
      t.element(find.byType(GroupChatScreen)),
    ).read(chatBubbleColorsProvider).outgoing;
    expect(fill('from Alice'), own.outgoing);
    final shade = ChatBubbleColor.plum.accentText(Brightness.light);
    expect(
      t
          .widget<Text>(find.byKey(Key('groupSender_${idOf('from Bob')}')))
          .style!
          .color,
      shade,
    );
    expect(
      t
          .widget<PersonAvatar>(
            find.byKey(Key('groupAvatar_${idOf('from Bob')}')),
          )
          .color,
      shade,
    );
    await tearDownPhones(t);
  });

  testWidgets('the history shows who was added, and where it starts for '
      'someone who joined later', (t) async {
    await setUpPhones(t);
    final mine = await bookClub(t, alice, bob);
    final theirs = await bookClub(t, bob, alice);
    await pump(t, GroupChatScreen(gid: mine));
    await settle(t, () => find.text('You added bob').evaluate().isNotEmpty);
    // Alice made this group: its history on her phone is complete.
    expect(find.byKey(const Key('historyStart')), findsNothing);

    await pump(t, GroupChatScreen(gid: theirs));
    await settle(
      t,
      () => find.byKey(const Key('historyStart')).evaluate().isNotEmpty,
    );
    expect(
      find.text('Messages sent before you joined aren’t shown.'),
      findsOneWidget,
    );
    await tearDownPhones(t);
  });

  testWidgets('a group row counts unread messages until the group is opened', (
    t,
  ) async {
    await setUpPhones(t);
    final gid = await bookClub(t, alice, bob);
    await pump(t, const ChatListScreen());
    final badge = find.byKey(ValueKey('unread-group-$gid'));
    await settle(t, () => find.text('Book club').evaluate().isNotEmpty);
    expect(badge, findsNothing);
    await t.runAsync(() async {
      await bob.service.send(gid, 'one');
      await bob.service.send(gid, 'two');
    });
    await settle(t, () => badge.evaluate().isNotEmpty);
    await settle(
      t,
      () => find
          .descendant(of: badge, matching: find.text('2'))
          .evaluate()
          .isNotEmpty,
    );
    // Lines about the group are not messages and are never counted.
    await t.tap(find.byKey(Key('group_$gid')));
    await settle(t, () => find.byType(GroupChatScreen).evaluate().isNotEmpty);
    await settle(t, () => find.text('two').evaluate().isNotEmpty);
    await t.pageBack();
    await settle(t, () => badge.evaluate().isEmpty);
    await tearDownPhones(t);
  });

  testWidgets("replying in a group shows the panel in that member's colour "
      'and sends a quote', (t) async {
    await setUpPhones(t);
    bob.service.ownColor = 'plum';
    final gid = await bookClub(t, alice, bob);
    await t.runAsync(() async {
      await bob.service.send(gid, 'from Bob');
      await until(
        () async =>
            (await texts(alice, gid)).contains('from Bob') &&
            alice.service.colorsOf(gid)['bob'] == 'plum',
        what: 'the message and the colour',
      );
    });
    await pump(t, GroupChatScreen(gid: gid));
    await settle(t, () => find.text('from Bob').evaluate().isNotEmpty);
    await t.longPress(find.text('from Bob'));
    await t.pumpAndSettle();
    await t.tap(action('reply'));
    await t.pumpAndSettle();

    final panel = find.byKey(const Key('replyComposerPreview'));
    expect(panel, findsOneWidget);
    final plum = ChatBubbleColor.plum.accentText(Brightness.light);
    expect(
      t.widget<ColoredBox>(find.byKey(const Key('replyPanelTab'))).color,
      plum,
    );
    expect(
      t.widget<Text>(find.byKey(const Key('replyPanelAuthor'))).style!.color,
      plum,
    );
    expect(find.descendant(of: panel, matching: find.text('bob')), findsOne);

    await t.enterText(find.byKey(const Key('composer')), 'to Bob');
    await t.pump();
    await t.tap(find.byKey(const Key('send')));
    await settle(t, () => panel.evaluate().isEmpty);
    // The send runs under the test's clock, so keep both clocks moving.
    var reached = false;
    for (var i = 0; i < 200 && !reached; i++) {
      await t.runAsync(() async {
        final got = (await bob.messages.watch('group-$gid').first)
            .where((m) => m.body == 'to Bob')
            .firstOrNull;
        reached =
            got?.quote?.body == 'from Bob' && got?.quote?.senderUid == 'bob';
        await Future<void>.delayed(const Duration(milliseconds: 25));
      });
      await t.pump(const Duration(milliseconds: 25));
    }
    expect(reached, isTrue, reason: 'the quote reaches Bob');
    // The bubble names the person quoted.
    await settle(t, () => find.text('to Bob').evaluate().isNotEmpty);
    expect(find.byType(MessageQuotePreview), findsOneWidget);
    expect(
      t.widget<MessageQuotePreview>(find.byType(MessageQuotePreview)).author,
      'bob',
    );
    await tearDownPhones(t);
  });

  testWidgets('people are ticked with round boxes when making a group', (
    t,
  ) async {
    await setUpPhones(t);
    await pump(t, const NewGroupScreen());
    final box = t.widget<CheckboxListTile>(find.byKey(const Key('pick_bob')));
    expect(box.checkboxShape, isA<CircleBorder>());
    await tearDownPhones(t);
  });

  testWidgets('a group can be muted on this phone, like a 1:1 chat', (t) async {
    await setUpPhones(t);
    final gid = await bookClub(t, alice, bob);
    await pump(t, const ChatListScreen());
    await settle(t, () => find.text('Book club').evaluate().isNotEmpty);
    final container = ProviderScope.containerOf(
      t.element(find.byType(ChatListScreen)),
    );
    final mark = find.byKey(ValueKey('muted-group-$gid'));
    expect(mark, findsNothing);
    await t.runAsync(() => bob.service.send(gid, 'one'));
    await settle(t, () => container.read(groupsBadgeProvider) == 1);

    // Holding the row offers the same choice as a 1:1 row.
    await t.longPress(find.byKey(Key('group_$gid')));
    await t.pumpAndSettle();
    await t.tap(find.text('Mute chat'));
    await settle(t, () => mark.evaluate().isNotEmpty);
    // Still counted on the row, but no longer on the app icon.
    expect(find.byKey(ValueKey('unread-group-$gid')), findsOneWidget);
    expect(container.read(groupsBadgeProvider), 0);
    expect(container.read(groupMutedProvider(gid)), isTrue);

    await t.longPress(find.byKey(Key('group_$gid')));
    await t.pumpAndSettle();
    await t.tap(find.text('Unmute chat'));
    await settle(t, () => mark.evaluate().isEmpty);
    expect(container.read(groupsBadgeProvider), 1);
    await tearDownPhones(t);
  });

  testWidgets('Group info mutes and unmutes the group', (t) async {
    await setUpPhones(t);
    final gid = await bookClub(t, alice, bob);
    await pump(t, GroupInfoScreen(gid: gid));
    final container = ProviderScope.containerOf(
      t.element(find.byType(GroupInfoScreen)),
    );
    expect(find.text('Mute'), findsOneWidget);
    await t.tap(find.byKey(const Key('muteGroup')));
    await settle(t, () => find.text('Unmute').evaluate().isNotEmpty);
    expect(container.read(groupMutedProvider(gid)), isTrue);
    await t.tap(find.byKey(const Key('muteGroup')));
    await settle(t, () => find.text('Mute').evaluate().isNotEmpty);
    expect(container.read(groupMutedProvider(gid)), isFalse);
    await tearDownPhones(t);
  });

  testWidgets('an administrator makes a member an administrator', (t) async {
    await setUpPhones(t);
    final gid = await bookClub(t, alice, bob);
    await pump(t, GroupInfoScreen(gid: gid));
    expect(find.text('Administrator'), findsOneWidget);
    // The row is below the fold: bring all of it on screen before tapping.
    await t.scrollUntilVisible(find.byKey(const Key('member_bob')), 200);
    await t.ensureVisible(find.byKey(const Key('member_bob')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('member_bob')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('removeAdmin')), findsNothing);
    await t.tap(find.byKey(const Key('makeAdmin')));
    await settle(t, () => alice.service.groups[gid]!.isAdmin('bob'));
    await settle(t, () => find.text('Administrator').evaluate().length == 2);
    // Now the choice is to take it away again.
    await t.ensureVisible(find.byKey(const Key('member_bob')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('member_bob')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('removeAdmin')), findsOneWidget);
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();
    await tearDownPhones(t);
  });

  testWidgets('someone invited is listed as invited until they join', (
    t,
  ) async {
    await setUpPhones(t);
    final gid = (await t.runAsync(() async {
      final gid = await alice.service.create('Book club', ['bob']);
      await until(
        () async => alice.service.invitedTo(gid).containsKey('bob'),
        what: 'invited',
      );
      return gid;
    }))!;
    await pump(t, GroupInfoScreen(gid: gid));
    await settle(
      t,
      () => find.byKey(const Key('invitedHeader')).evaluate().isNotEmpty,
    );
    expect(find.textContaining('1 person, 1 invited'), findsOneWidget);
    final row = find.byKey(const Key('member_bob'));
    await t.scrollUntilVisible(row, 200);
    expect(
      find.descendant(of: row, matching: find.text('Invited')),
      findsOneWidget,
    );
    // Not a member yet, so not offered as an administrator.
    await t.tap(row);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('makeAdmin')), findsNothing);

    await t.runAsync(() => bob.service.accept(gid));
    await settle(
      t,
      () => find.byKey(const Key('invitedHeader')).evaluate().isEmpty,
    );
    await t.scrollUntilVisible(find.textContaining('2 people'), -200);
    expect(find.textContaining('2 people'), findsOneWidget);
    await tearDownPhones(t);
  });
}
