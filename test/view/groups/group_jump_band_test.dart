// In a group too, the highlight after a jump (here to a pinned message) is a
// square band from one screen edge to the other, as tall as the message's
// row (issue 251). The row itself keeps the timeline's side inset.
import 'dart:async';
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/src/app/group_providers.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat/message_menu_parts.dart';
import 'package:fireplace/src/view/chat/widgets/message_flash.dart';
import 'package:fireplace/src/view/groups/group_chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_group_server.dart';
import '../../support/group_phones.dart';
import '../../support/jump_band.dart';
import '../../support/ui_fixture.dart';

void main() {
  late Directory root;
  late FakeGroupServer server;
  late Phone alice, bob;
  late String gid;
  final boundary = GlobalKey();

  /// Alice (this phone) and Bob in "Book club"; Bob's message is pinned.
  Future<void> story(WidgetTester t) => t.runAsync(() async {
    root = await Directory.systemTemp.createTemp('group_jump_band');
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

  Future<void> open(WidgetTester t, Size size, FakeViewPadding padding) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    t.view.padding = padding;
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
        child: RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            theme: fireplaceTheme(Brightness.light),
            home: GroupChatScreen(gid: gid),
          ),
        ),
      ),
    );
    await settle(t, () => find.text('from Alice').evaluate().isNotEmpty);
  }

  /// The id of Bob's message, from the row that shows it.
  String bobs(WidgetTester t) => t
      .widget<MessageFlash>(
        find.ancestor(
          of: find.text('from Bob').last,
          matching: find.byType(MessageFlash),
        ),
      )
      .messageId;

  /// Pins Bob's message from its menu, then jumps to it from the pinned bar.
  Future<void> jumpToPinned(WidgetTester t) async {
    await t.longPress(find.text('from Bob'));
    await t.pumpAndSettle();
    final pin = find.byKey(const ValueKey('messageAction-pin'));
    await t.ensureVisible(pin);
    await t.pumpAndSettle();
    await t.tap(pin);
    await t.pumpAndSettle();
    await settle(
      t,
      () => find.byKey(const Key('pinnedMessages')).evaluate().isNotEmpty,
    );
    await t.tap(find.byKey(const Key('pinnedMessages')));
    await settle(t, () {
      return jumpBandShown(t, bobs(t)) == 1;
    });
  }

  for (final (name, size, padding) in [
    ('portrait', const Size(390, 844), const FakeViewPadding(top: 47)),
    (
      'landscape',
      const Size(844, 390),
      const FakeViewPadding(left: 47, right: 47, bottom: 21),
    ),
  ]) {
    testWidgets('the band runs from edge to edge, $name', (t) async {
      await story(t);
      await open(t, size, padding);
      await jumpToPinned(t);

      final id = bobs(t);
      final bandRect = t.getRect(jumpBand(id));
      final row = t.getRect(flashedRow(id));
      expect(bandRect.left, 0);
      expect(bandRect.right, size.width);
      expect(bandRect.top, row.top);
      expect(bandRect.height, row.height);
      expect(row.left, MessageMenuMetrics.edge);
      expect(row.right, size.width - MessageMenuMetrics.edge);

      final decoration =
          t.widget<AnimatedContainer>(jumpBand(id)).decoration!
              as BoxDecoration;
      expect(decoration.borderRadius, isNull, reason: 'square corners');
      for (final x in [0.0, size.width - 1]) {
        final painted = await paintedPixel(
          t,
          boundary,
          Offset(x, bandRect.center.dy),
        );
        expect(
          painted.toARGB32(),
          decoration.color!.toARGB32(),
          reason: 'pixel at x $x',
        );
      }
      await tearDownPhones(t);
    });
  }
}
