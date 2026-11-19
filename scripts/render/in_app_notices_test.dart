// In-app notices for review (issue 233): the message banner with previews on
// and off, a bottom toast, in light and dark, and the banner falling in.
// Not part of the byte-identical catalog.
//   TZ=UTC flutter test scripts/render/in_app_notices_test.dart
//   python scripts/render/frames_to_gif.py build/frames/notice-fall
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat/chat_route_observer.dart';
import 'package:fireplace/src/view/chat_list/chat_list_screen.dart';
import 'package:fireplace/src/view/notifications/in_app_notice.dart';
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
  File('build/notices/$path')
    ..createSync(recursive: true)
    ..writeAsBytesSync(png!);
}

Future<(GlobalKey, UiFixture)> _mount(
  WidgetTester t,
  Brightness brightness, {
  bool previews = true,
}) async {
  // Real blurred shadows, not the widget-test outlines; each test puts the
  // setting back at its end (the framework checks before teardown).
  debugDisableShadows = false;
  final f = UiFixture();
  await f.seed();
  addTearDown(f.session.close);
  await f.session.chatPreferences.previews(previews);
  t.view.physicalSize = _size;
  t.view.devicePixelRatio = 1;
  t.view.padding = const FakeViewPadding(top: 47);
  addTearDown(t.view.reset);
  final boundary = GlobalKey();
  final nav = GlobalKey<NavigatorState>();
  final theme = fireplaceTheme(brightness);
  await t.pumpWidget(
    ProviderScope(
      overrides: f.overrides,
      child: RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          navigatorKey: nav,
          navigatorObservers: [chatRouteObserver],
          theme: theme.copyWith(
            textTheme: theme.textTheme.apply(
              fontFamilyFallback: const ['PreviewEmoji'],
            ),
          ),
          builder: (context, child) =>
              InAppNoticeHost(navigatorKey: nav, child: child!),
          home: const ChatListScreen(),
        ),
      ),
    ),
  );
  await settleUi(t);
  return (boundary, f);
}

Future<void> _arrive(WidgetTester t, UiFixture f, String id) async {
  await f.chat.store.add(
    message(
      id: id,
      body: 'See you in the garden ☕ I will bring the good cups',
      at: fixtureTime.add(const Duration(minutes: 1)),
    ),
  );
  await settleUi(t);
}

void main() {
  setUpAll(loadFonts);

  for (final brightness in Brightness.values) {
    final mode = brightness.name;
    for (final previews in [true, false]) {
      testWidgets('banner $mode previews $previews', (t) async {
        final (boundary, f) = await _mount(t, brightness, previews: previews);
        await _arrive(t, f, 'one');
        await t.pump(const Duration(seconds: 1));
        await _write(
          t,
          boundary,
          '$mode-banner-${previews ? 'preview' : 'no-preview'}.png',
        );
        debugDisableShadows = true;
      });
    }

    testWidgets('toast $mode', (t) async {
      final (boundary, _) = await _mount(t, brightness);
      ScaffoldMessenger.of(t.element(find.byType(ChatListScreen)))
          .showSnackBar(const SnackBar(content: Text('Reported as spam.')));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      await _write(t, boundary, '$mode-toast.png');
      debugDisableShadows = true;
    });
  }

  testWidgets('the banner falls in', (t) async {
    final (boundary, f) = await _mount(t, Brightness.light);
    await f.chat.store.add(
      message(
        id: 'fall',
        body: 'See you in the garden ☕',
        at: fixtureTime.add(const Duration(minutes: 1)),
      ),
    );
    for (var i = 0; i < 18; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await t.pump(const Duration(milliseconds: 30));
      final path = '../frames/notice-fall/${i.toString().padLeft(3, '0')}.png';
      await _write(t, boundary, path);
    }
    debugDisableShadows = true;
  });
}
