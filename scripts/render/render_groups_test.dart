// Renders the group screens (decision 0050) into build/renders/groups/, for
// review and for pull requests:
//
//   bash scripts/build_crypto_host.sh
//   TZ=UTC flutter test scripts/render/render_groups_test.dart
//
// Unlike the catalog in render_screens_test.dart, these use real group
// services over the Rust MLS core (there is no fake of MLS), so group ids and
// times differ between runs and the images are not byte-identical. They are
// widget renders, not device screenshots, and the names are fictional.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/src/app/chat_color_preference.dart';
import 'package:fireplace/src/app/group_providers.dart';
import 'package:fireplace/src/model/groups/group_models.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat_list/chat_list_screen.dart';
import 'package:fireplace/src/view/groups/group_chat_screen.dart';
import 'package:fireplace/src/view/groups/group_info_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/support/fake_group_server.dart';
import '../../test/support/group_phones.dart';
import '../../test/support/ui_fixture.dart';
import 'render_screens_test.dart' show loadFonts;

void main() {
  late Directory root;
  late FakeFirebaseFirestore db;
  late FakeGroupServer server;
  late Phone alice, bob, carol, dana;
  late String mine, theirs;

  /// A few people, two groups and some conversation. Alice is this phone.
  Future<void> story() async {
    root = await Directory.systemTemp.createTemp('group_renders');
    db = FakeFirebaseFirestore();
    server = FakeGroupServer(db);
    alice = await Phone.create(db, 'alice', root);
    bob = await Phone.create(db, 'bob_jones', root);
    carol = await Phone.create(db, 'carol', root);
    dana = await Phone.create(db, 'dana', root);
    for (final p in [alice, bob, carol, dana]) {
      server.watchAccount(p.uid);
    }
    bob.service.ownColor = 'plum';
    carol.service.ownColor = 'forest';

    Future<void> said(Phone from, String gid, String text) async {
      await from.service.send(gid, text);
      await until(
        () async => (await texts(alice, gid)).contains(text),
        what: text,
      );
    }

    mine = await alice.service.create('Book club', ['bob_jones', 'carol']);
    for (final p in [bob, carol]) {
      await until(
        () async => p.service.invitations.any((i) => i.gid == mine),
        what: 'invitation',
      );
      await p.service.accept(mine);
      await until(
        () async => alice.service.colorsOf(mine).containsKey(p.uid),
        what: 'colour of ${p.uid}',
      );
    }
    await alice.service.send(mine, 'Shall we start the new one this week?');
    await said(bob, mine, 'Yes. I have the first three chapters done');
    await said(bob, mine, 'It gets going after the second');
    await said(carol, mine, 'Thursday works for me');
    await alice.service.send(mine, 'Thursday at 7, then');
    await alice.service.setAdmin(mine, 'bob_jones', admin: true);
    await alice.service.invite(mine, 'dana');
    await until(
      () async => alice.service.invitedTo(mine).containsKey('dana'),
      what: 'Dana invited',
    );
    await said(carol, mine, 'I will bring the tea');

    theirs = await bob.service.create('Hill walkers', ['alice']);
    await until(
      () async => alice.service.invitations.any((i) => i.gid == theirs),
      what: 'invitation',
    );
    await alice.service.accept(theirs);
    await until(
      () async => bob.service.groups[theirs]!.members.length == 2,
      what: 'joined',
    );
    await said(bob, theirs, 'Welcome. Saturday is the ridge walk');
  }

  Future<void> settle(WidgetTester t, [int rounds = 12]) async {
    for (var i = 0; i < rounds; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await t.pump(const Duration(milliseconds: 25));
    }
  }

  for (final brightness in Brightness.values) {
    testWidgets('group screens, ${brightness.name}', (t) async {
      await t.runAsync(loadFonts);
      await t.runAsync(story);
      final previousShadows = debugDisableShadows;
      debugDisableShadows = false;
      addTearDown(() => debugDisableShadows = previousShadows);
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);

      Future<void> render(
        String name,
        Widget screen, {
        Future<void> Function()? act,
      }) async {
        final fixture = UiFixture();
        await fixture.seed();
        final boundary = GlobalKey();
        await t.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [
              ...fixture.overrides,
              groupServiceProvider.overrideWithValue(alice.service),
              groupContactsProvider.overrideWithValue(const ['bob_jones']),
            ],
            child: RepaintBoundary(
              key: boundary,
              child: Consumer(
                builder: (context, ref, _) {
                  final theme = fireplaceTheme(
                    brightness,
                    accent: ref.watch(
                      chatBubbleColorsProvider.select((c) => c.outgoing),
                    ),
                  );
                  return MaterialApp(
                    debugShowCheckedModeBanner: false,
                    theme: theme.copyWith(
                      textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
                    ),
                    home: screen,
                  );
                },
              ),
            ),
          ),
        );
        await settle(t);
        await act?.call();
        await settle(t);
        final renderer =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final png = await t.runAsync(() async {
          final image = await renderer.toImage(pixelRatio: 2);
          try {
            return (await image.toByteData(format: ui.ImageByteFormat.png))!
                .buffer
                .asUint8List();
          } finally {
            image.dispose();
          }
        });
        File('build/renders/groups/${brightness.name}-$name.png')
          ..createSync(recursive: true)
          ..writeAsBytesSync(png!);
      }

      await render('list', const ChatListScreen());
      await render('conversation', GroupChatScreen(gid: mine));
      await render(
        'conversation-menu',
        GroupChatScreen(gid: mine),
        act: () async {
          await t.longPress(find.text('Thursday at 7, then'));
          await t.pump(const Duration(milliseconds: 600));
        },
      );
      await render(
        'conversation-editing',
        GroupChatScreen(gid: mine),
        act: () async {
          await t.longPress(find.text('Thursday at 7, then'));
          await t.pump(const Duration(milliseconds: 600));
          await t.tap(find.byKey(const ValueKey('messageAction-edit')));
          // The menu closes, then the composer takes the text.
          for (var i = 0; i < 10; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
        },
      );
      await render('joined-later', GroupChatScreen(gid: theirs));
      await render('info', GroupInfoScreen(gid: mine));

      await t.pumpWidget(const SizedBox());
      await t.runAsync(() async {
        for (final p in [alice, bob, carol, dana]) {
          await p.service.close();
        }
        await server.close();
        await root.delete(recursive: true);
      });
      // The test binding checks this is back before the body ends.
      debugDisableShadows = previousShadows;
      expect(GroupLimits.maxMembers, 16);
    });
  }
}
