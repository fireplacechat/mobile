// The jump highlight for review (issue 251): a 1:1 chat opened at a search
// result and a group jumped to a pinned message, in light and dark, portrait
// and landscape with side safe areas. Not part of the byte-identical catalog;
// the group uses real group services over the Rust MLS core.
//   bash scripts/build_crypto_host.sh
//   TZ=UTC flutter test scripts/render/render_jump_band_test.dart
// Images go to build/renders/jump-band/.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/src/app/group_providers.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat/chat_route_observer.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:fireplace/src/view/chat/widgets/message_flash.dart';
import 'package:fireplace/src/view/groups/group_chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/support/fake_group_server.dart';
import '../../test/support/group_phones.dart';
import '../../test/support/ui_fixture.dart';
import 'render_screens_test.dart' show loadFonts;

const _portrait = (Size(390, 780), FakeViewPadding(top: 47, bottom: 34));
const _landscape = (
  Size(812, 375),
  FakeViewPadding(left: 47, right: 47, bottom: 21),
);

Future<void> _write(WidgetTester t, GlobalKey boundary, String name) async {
  final renderer =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final png = await t.runAsync(() async {
    final image = await renderer.toImage(pixelRatio: 2);
    try {
      return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
          .asUint8List();
    } finally {
      image.dispose();
    }
  });
  File('build/renders/jump-band/$name.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(png!);
}

/// How opaque the highlight behind the row holding [text] is. Written so it
/// reads the same before and after issue 251: the first AnimatedContainer
/// under the row's MessageFlash is the tint either way.
double _shown(WidgetTester t, String text) {
  if (find.text(text).evaluate().isEmpty) return 0;
  final flash = find.ancestor(
    of: find.text(text).last,
    matching: find.byType(MessageFlash),
  );
  if (flash.evaluate().isEmpty) return 0;
  final tint = find
      .descendant(of: flash, matching: find.byType(AnimatedContainer))
      .first;
  final box = t.renderObject(tint) as RenderDecoratedBox;
  return (box.decoration as BoxDecoration).color!.a;
}

/// Lets the real event loop and the test clock run until the highlight
/// behind [text] has fully faded in.
Future<void> _untilLit(WidgetTester t, String text) async {
  for (var i = 0; i < 80 && _shown(t, text) < 1; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await t.pump(const Duration(milliseconds: 25));
  }
  expect(_shown(t, text), 1);
}

Widget _app(GlobalKey boundary, Brightness brightness, Widget home) {
  final theme = fireplaceTheme(brightness);
  return RepaintBoundary(
    key: boundary,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorObservers: [chatRouteObserver],
      theme: theme.copyWith(
        textTheme: theme.textTheme.apply(
          fontFamily: 'Roboto',
          fontFamilyFallback: const ['PreviewEmoji'],
        ),
      ),
      home: home,
    ),
  );
}

void _view(WidgetTester t, (Size, FakeViewPadding) layout) {
  t.view.physicalSize = layout.$1;
  t.view.devicePixelRatio = 1;
  t.view.padding = layout.$2;
  addTearDown(t.view.reset);
}

void main() {
  setUpAll(loadFonts);

  for (final brightness in Brightness.values) {
    for (final (orientation, layout) in [
      ('portrait', _portrait),
      ('landscape', _landscape),
    ]) {
      final name = '${brightness.name}-chat-$orientation';
      testWidgets(name, (t) async {
        // Real blurred shadows; put back at the end of the body, where the
        // framework checks it.
        debugDisableShadows = false;
        _view(t, layout);
        final f = UiFixture();
        await f.seed();
        for (var i = 0; i < 20; i++) {
          await f.chat.store.add(
            message(
              id: 'later-$i',
              body: 'Later message $i',
              at: fixtureTime.add(Duration(hours: 1, minutes: i)),
            ),
          );
        }
        addTearDown(f.session.close);
        final boundary = GlobalKey();
        await t.pumpWidget(
          ProviderScope(
            overrides: f.overrides,
            child: _app(
              boundary,
              brightness,
              const ChatScreen(chatId: 'alice_fred', initialMessageId: '1'),
            ),
          ),
        );
        await settleUi(t);
        await _untilLit(t, 'Are we still on for Saturday?');
        await _write(t, boundary, name);
        debugDisableShadows = true;
      });
    }
  }

  for (final brightness in Brightness.values) {
    testWidgets('${brightness.name} group', (t) async {
      final previousShadows = debugDisableShadows;
      late Directory root;
      late FakeGroupServer server;
      late Phone alice, bob, carol;
      late String gid;
      await t.runAsync(() async {
        root = await Directory.systemTemp.createTemp('jump_band_renders');
        final db = FakeFirebaseFirestore();
        server = FakeGroupServer(db);
        alice = await Phone.create(db, 'alice', root);
        bob = await Phone.create(db, 'bob_jones', root);
        carol = await Phone.create(db, 'carol', root);
        for (final p in [alice, bob, carol]) {
          server.watchAccount(p.uid);
        }
        bob.service.ownColor = 'plum';
        carol.service.ownColor = 'forest';
        gid = await alice.service.create('Book club', ['bob_jones', 'carol']);
        for (final p in [bob, carol]) {
          await until(
            () async => p.service.invitations.any((i) => i.gid == gid),
            what: 'invitation',
          );
          await p.service.accept(gid);
          await until(
            () async => alice.service.colorsOf(gid).containsKey(p.uid),
            what: 'colour of ${p.uid}',
          );
        }
        Future<void> said(Phone from, String text) async {
          await from.service.send(gid, text);
          await until(
            () async => (await texts(alice, gid)).contains(text),
            what: text,
          );
        }

        await said(alice, 'Shall we start the new one this week?');
        await said(bob, 'Yes. I have the first three chapters done');
        await said(carol, 'Thursday works for me');
        for (final (i, line) in const [
          'Thursday at 7, then',
          'Who is bringing the biscuits?',
          'I can',
          'Same room as last time?',
          'Yes, the one upstairs',
          'Chapter four is the best so far',
          'No spoilers please',
          'Fine, fine',
          'See you all there',
        ].indexed) {
          await said([alice, bob, carol][i % 3], line);
        }
      });

      Future<void> settle() async {
        for (var i = 0; i < 12; i++) {
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
          await t.pump(const Duration(milliseconds: 25));
        }
      }

      // One phone for both pictures: the pin stays.
      final f = UiFixture();
      await f.seed();
      for (final (orientation, layout) in [
        ('portrait', _portrait),
        ('landscape', _landscape),
      ]) {
        debugDisableShadows = false;
        _view(t, layout);
        final boundary = GlobalKey();
        await t.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [
              ...f.overrides,
              groupServiceProvider.overrideWithValue(alice.service),
              groupContactsProvider.overrideWithValue(const [
                'bob_jones',
                'carol',
              ]),
            ],
            child: _app(boundary, brightness, GroupChatScreen(gid: gid)),
          ),
        );
        await settle();
        const pinned = 'Yes. I have the first three chapters done';
        if (find.byKey(const Key('pinnedMessages')).evaluate().isEmpty) {
          final list = t
              .widget<ListView>(find.byKey(const Key('groupMessages')))
              .controller!;
          list.jumpTo(list.position.maxScrollExtent);
          await settle();
          await t.longPress(find.text(pinned));
          await t.pump(const Duration(milliseconds: 600));
          final pin = find.byKey(const ValueKey('messageAction-pin'));
          await t.ensureVisible(pin);
          await t.pump(const Duration(milliseconds: 300));
          await t.tap(pin);
          for (var i = 0; i < 10; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
          await settle();
          // Back to the newest, so the pinned bar has somewhere to jump.
          list.jumpTo(0);
          await settle();
        }
        await t.tap(find.byKey(const Key('pinnedMessages')));
        await _untilLit(t, pinned);
        await _write(t, boundary, '${brightness.name}-group-$orientation');
        await t.pumpWidget(const SizedBox());
        await settle();
      }

      await t.runAsync(() async {
        for (final p in [alice, bob, carol]) {
          await p.service.close();
        }
        await server.close();
        await root.delete(recursive: true);
      });
      debugDisableShadows = previousShadows;
    });
  }
}
