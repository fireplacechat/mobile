// Frames of the Android swipe back from Settings and Invite friends (issue
// 236), for review as animations; not part of the byte-identical catalog.
//   TZ=UTC flutter test scripts/render/swipe_back_frames_test.dart
//   python scripts/render/frames_to_gif.py build/frames/<name>
// - swipe-back-settings, swipe-back-invites: drag right from the middle of
//   the page, past halfway, and let go: the chat list comes back.
// - swipe-back-settle: a short drag, released: the page settles back.
// Each also writes <name>-mid.png, the page halfway under the finger.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/src/app/invite_providers.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat_list/chat_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/support/ui_fixture.dart';
import 'render_screens_test.dart';

const _size = Size(390, 780);

Future<void> _write(WidgetTester t, GlobalKey boundary, String path) async {
  final renderer =
      boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final png = await t.runAsync(() async {
    final image = await renderer.toImage(pixelRatio: 2);
    try {
      return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
          .asUint8List();
    } finally {
      image.dispose();
    }
  });
  File('build/frames/$path')
    ..createSync(recursive: true)
    ..writeAsBytesSync(png!);
}

Future<GlobalKey> _mount(WidgetTester t) async {
  final fixture = UiFixture();
  await fixture.seed();
  addTearDown(fixture.session.close);
  final db = FakeFirebaseFirestore();
  await t.runAsync(
    () => db.doc('users/alice').set({
      'username': 'alice',
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 11, 14)),
    }),
  );
  t.view.physicalSize = _size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final boundary = GlobalKey();
  final theme = fireplaceTheme(Brightness.light);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        ...fixture.overrides,
        firestoreProvider.overrideWithValue(db),
        inviteClockProvider.overrideWithValue(
          () => DateTime.utc(2026, 11, 14, 12),
        ),
      ],
      child: RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme.copyWith(
            platform: TargetPlatform.android,
            textTheme: theme.textTheme.apply(
              fontFamilyFallback: const ['PreviewEmoji'],
            ),
          ),
          home: const ChatListScreen(),
        ),
      ),
    ),
  );
  await settleUi(t);
  return boundary;
}

Future<void> _swipe(
  WidgetTester t,
  String name,
  String button, {
  required double distance,
}) async {
  final boundary = await _mount(t);
  await t.tap(find.byKey(Key(button)));
  await t.pumpAndSettle();
  var frame = 0;
  Future<void> shot() =>
      _write(t, boundary, '$name/${(frame++).toString().padLeft(3, '0')}.png');
  await shot();
  final gesture = await t.startGesture(Offset(_size.width / 2, 420));
  for (var moved = 0.0; moved < distance; moved += 13) {
    await gesture.moveBy(const Offset(13, 0));
    await t.pump(const Duration(milliseconds: 40));
    await shot();
    if ((moved - _size.width / 2).abs() < 7) {
      await _write(t, boundary, '$name-mid.png');
    }
  }
  if (distance < _size.width / 2) {
    await _write(t, boundary, '$name-mid.png');
    await t.pump(const Duration(milliseconds: 300)); // held: not a fling
  }
  await gesture.up();
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 40));
    await shot();
  }
  await t.pumpAndSettle();
  await shot();
}

void main() {
  setUpAll(loadFonts);

  testWidgets('swipe back from Settings', (t) async {
    await _swipe(t, 'swipe-back-settings', 'settings', distance: 260);
  });

  testWidgets('swipe back from Invite friends', (t) async {
    await _swipe(t, 'swipe-back-invites', 'inviteFriends', distance: 260);
  });

  testWidgets('a short swipe settles back', (t) async {
    await _swipe(t, 'swipe-back-settle', 'settings', distance: 90);
  });
}
