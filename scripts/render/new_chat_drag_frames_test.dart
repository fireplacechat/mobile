// Frames of the New chat panel dragged down (issue 239), for review as an
// animation; not part of the byte-identical catalog.
//   TZ=UTC flutter test scripts/render/new_chat_drag_frames_test.dart
//   python scripts/render/frames_to_gif.py build/frames/<name>
// - new-chat-drag-close: dragged past halfway and let go: it closes.
// - new-chat-drag-settle: a short drag, let go: it settles back.
// Each also writes <name>-mid.png, the panel partway down.
import 'dart:io';
import 'dart:ui' as ui;

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

Future<void> _drag(
  WidgetTester t,
  String name, {
  required double distance,
}) async {
  final previousShadows = debugDisableShadows;
  debugDisableShadows = false;
  final fixture = UiFixture();
  await fixture.seed();
  addTearDown(fixture.session.close);
  t.view.physicalSize = _size;
  t.view.devicePixelRatio = 1;
  t.view.padding = const FakeViewPadding(top: 47);
  addTearDown(t.view.reset);
  final boundary = GlobalKey();
  final theme = fireplaceTheme(Brightness.light);
  await t.pumpWidget(
    ProviderScope(
      overrides: fixture.overrides,
      child: RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme.copyWith(
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
  await t.tap(find.byKey(const Key('newChat')));
  await t.pumpAndSettle();
  var frame = 0;
  Future<void> shot() =>
      _write(t, boundary, '$name/${(frame++).toString().padLeft(3, '0')}.png');
  await shot();
  final gesture = await t.startGesture(
    t.getCenter(find.byKey(const Key('newChatList'))),
  );
  for (var moved = 0.0; moved < distance; moved += 20) {
    await gesture.moveBy(const Offset(0, 20));
    await t.pump(const Duration(milliseconds: 40));
    await shot();
    if ((moved - distance * .6).abs() < 10) {
      await _write(t, boundary, '$name-mid.png');
    }
  }
  await t.pump(const Duration(milliseconds: 300)); // held: not a flick
  await gesture.up();
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 40));
    await shot();
  }
  await t.pumpAndSettle();
  await shot();
  debugDisableShadows = previousShadows;
}

void main() {
  setUpAll(loadFonts);

  testWidgets('dragged down and closed', (t) async {
    await _drag(t, 'new-chat-drag-close', distance: 520);
  });

  testWidgets('a short drag settles back', (t) async {
    await _drag(t, 'new-chat-drag-settle', distance: 160);
  });
}
