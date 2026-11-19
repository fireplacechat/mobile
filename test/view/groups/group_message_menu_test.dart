// Holding a message in a group does what it does in a 1:1 chat (issue 209):
// the same controls and icons, one Delete with the 1:1 sheet, Select, Info,
// Pin and Forward.
import 'dart:async';
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/src/app/group_providers.dart';
import 'package:fireplace/src/styles/action_icons.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat/forward/forward_message.dart';
import 'package:fireplace/src/view/groups/group_chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_group_server.dart';
import '../../support/group_phones.dart';
import '../../support/ui_fixture.dart';

void main() {
  late Directory root;
  late FakeGroupServer server;
  late Phone alice, bob;
  late String gid;

  /// Alice (this phone) and Bob in "Book club", one message each.
  Future<void> story(WidgetTester t) => t.runAsync(() async {
    root = await Directory.systemTemp.createTemp('group_menu');
    final db = FakeFirebaseFirestore();
    server = FakeGroupServer(db);
    alice = await Phone.create(db, 'alice', root);
    bob = await Phone.create(db, 'bob', root);
    server
      ..watchAccount('alice')
      ..watchAccount('bob');
    gid = await alice.service.create('Book club', ['bob']);
    await until(
      () async => bob.service.invitations.any((i) => i.gid == gid),
      what: 'invitation',
    );
    await bob.service.accept(gid);
    await until(
      () async => alice.service.groups[gid]!.members.length == 2,
      what: 'joined',
    );
    await bob.service.send(gid, 'from Bob');
    await until(
      () async => (await texts(alice, gid)).contains('from Bob'),
      what: 'delivered',
    );
    await alice.service.send(gid, 'from Alice');
  });

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

  Future<void> settle(WidgetTester t, bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await t.pump(const Duration(milliseconds: 25));
    }
    expect(done(), isTrue);
  }

  Finder action(String id) => find.byKey(ValueKey('messageAction-$id'));

  Future<UiFixture> open(WidgetTester t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final f = UiFixture();
    await f.seed();
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          ...f.overrides,
          groupServiceProvider.overrideWithValue(alice.service),
          groupContactsProvider.overrideWithValue(const ['bob']),
        ],
        child: MaterialApp(
          theme: fireplaceTheme(Brightness.light),
          home: GroupChatScreen(gid: gid),
        ),
      ),
    );
    await settle(t, () => find.text('from Alice').evaluate().isNotEmpty);
    return f;
  }

  Future<void> hold(WidgetTester t, String text) async {
    await t.longPress(find.text(text));
    await t.pumpAndSettle();
  }

  Future<void> choose(WidgetTester t, String id) async {
    await t.ensureVisible(action(id));
    await t.pumpAndSettle();
    await t.tap(action(id));
    await t.pumpAndSettle();
  }

  testWidgets('the menu has the 1:1 controls and icons', (t) async {
    await story(t);
    await open(t);
    await hold(t, 'from Alice');
    for (final id in [
      'reply',
      'edit',
      'forward',
      'copy',
      'select',
      'info',
      'pin',
      'delete',
    ]) {
      expect(action(id), findsOneWidget, reason: id);
    }
    // No second delete squeezed into the menu.
    expect(action('deleteForEveryone'), findsNothing);
    expect(action('deleteForMe'), findsNothing);
    expect(
      find.descendant(
        of: action('copy'),
        matching: find.byIcon(ActionIcons.copy),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: action('delete'),
        matching: find.byIcon(ActionIcons.delete),
      ),
      findsOneWidget,
    );
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();
    await tearDownPhones(t);
  });

  testWidgets('Select picks messages; Delete removes them from this phone', (
    t,
  ) async {
    await story(t);
    await open(t);
    await hold(t, 'from Bob');
    await choose(t, 'select');
    expect(find.text('1 Selected'), findsOneWidget);
    // The composer gives way to the selection bar, as in a 1:1 chat.
    expect(find.byKey(const Key('composer')), findsNothing);
    await t.tap(find.text('from Alice'));
    await t.pumpAndSettle();
    expect(find.text('2 Selected'), findsOneWidget);

    await t.tap(find.byKey(const Key('deleteSelectedMessages')));
    await t.pumpAndSettle();
    // Bob's message is among them: only "for me" is offered.
    expect(find.byKey(const Key('confirmRemoteDelete')), findsNothing);
    await t.tap(find.byKey(const Key('confirmDeleteForMe')));
    await settle(
      t,
      () =>
          find.text('from Bob').evaluate().isEmpty &&
          find.text('from Alice').evaluate().isEmpty,
    );
    expect(find.byKey(const Key('selectionCount')), findsNothing);
    expect(find.byKey(const Key('composer')), findsOneWidget);
    // Still on Bob's phone: nothing was sent.
    expect(await t.runAsync(() => texts(bob, gid)), contains('from Alice'));
    await tearDownPhones(t);
  });

  testWidgets('Delete All deletes what you sent for everyone', (t) async {
    await story(t);
    await open(t);
    await hold(t, 'from Alice');
    await choose(t, 'select');
    await t.tap(find.byKey(const Key('deleteAllMessages')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('confirmDeleteAllMessages')));
    await settle(t, () => find.text('from Alice').evaluate().isEmpty);
    expect(find.text('from Bob'), findsNothing);
    await t.runAsync(
      () => until(
        () async => !(await texts(bob, gid)).contains('from Alice'),
        what: 'deleted for Bob',
      ),
    );
    await tearDownPhones(t);
  });

  testWidgets('Pin shows the message above the conversation', (t) async {
    await story(t);
    await open(t);
    await hold(t, 'from Bob');
    await choose(t, 'pin');
    await settle(
      t,
      () => find.byKey(const Key('pinnedMessages')).evaluate().isNotEmpty,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('pinnedMessages')),
        matching: find.text('from Bob'),
      ),
      findsOneWidget,
    );
    await t.tap(find.byKey(const Key('pinnedMessages')));
    await t.pumpAndSettle();
    // Held again, it offers to unpin. (The first match is the pinned bar.)
    await t.longPress(find.text('from Bob').last);
    await t.pumpAndSettle();
    await t.ensureVisible(action('pin'));
    expect(
      find.descendant(of: action('pin'), matching: find.text('Unpin')),
      findsOneWidget,
    );
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();
    await tearDownPhones(t);
  });

  testWidgets('Info and Copy work as in a 1:1 chat', (t) async {
    String? copied;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await story(t);
    await open(t);
    await hold(t, 'from Bob');
    await choose(t, 'info');
    expect(find.text('Received'), findsOneWidget);
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();

    await hold(t, 'from Bob');
    await choose(t, 'copy');
    expect(copied, 'from Bob');
    expect(find.text('Message copied'), findsOneWidget);
    await tearDownPhones(t);
  });

  testWidgets('Forward offers your chats', (t) async {
    await story(t);
    await open(t);
    await hold(t, 'from Alice');
    await choose(t, 'forward');
    expect(find.byType(ForwardMessageScreen), findsOneWidget);
    // The group is open, so its message can be forwarded.
    expect(find.text('Conversation unavailable'), findsNothing);
    expect(
      find.byKey(const ValueKey('forwardRecipient-alice_bob')),
      findsOneWidget,
    );
    await tearDownPhones(t);
  });
}
