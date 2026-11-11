// One frame of a message sliding up from behind the composer.
// Not part of the byte-identical catalog. TZ=UTC.
// flutter test scripts/render/send_slide_frame_test.dart
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:fireplace/src/view/chat/widgets/rising_send.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/support/ui_fixture.dart';
import 'render_screens_test.dart';

Future<void> _write(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
) async {
  final renderer =
      boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final png = await tester.runAsync(() async {
    final image = await renderer.toImage(pixelRatio: 2);
    try {
      return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
          .asUint8List();
    } finally {
      image.dispose();
    }
  });
  File('build/renders/$name')
    ..createSync(recursive: true)
    ..writeAsBytesSync(png!);
}

void main() {
  setUpAll(loadFonts);
  testWidgets('dark send slides up from behind the composer', (tester) async {
    final previousShadows = debugDisableShadows;
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = previousShadows);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fixture = UiFixture();
    await fixture.seed();
    addTearDown(fixture.session.close);
    fixture.chat.sendHold = Completer<void>();
    final boundary = GlobalKey();
    final theme = fireplaceTheme(Brightness.dark);
    await tester.pumpWidget(
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
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(viewInsets: const EdgeInsets.only(bottom: 280)),
              child: child!,
            ),
            home: const ChatScreen(chatId: 'alice_fred'),
          ),
        ),
      ),
    );
    await settleUi(tester);
    await tester.enterText(
      find.byKey(const Key('composer')),
      'See you at two.',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'dark-send-sliding.png');
    await tester.pump(RisingSend.duration);
    expect(tester.takeException(), isNull);
    await _write(tester, boundary, 'dark-send-slid.png');
    fixture.chat.sendHold!.complete();
    await tester.pump();
    debugDisableShadows = previousShadows;
  });
}
