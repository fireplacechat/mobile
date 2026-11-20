// The highlight after a jump is a square band from one screen edge to the
// other, as tall as the message's row (issue 251). The row itself keeps the
// timeline's side inset.
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat/chat_route_observer.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:fireplace/src/view/chat/message_menu_parts.dart';
import 'package:fireplace/src/view/chat/timeline_scroll.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/jump_band.dart';
import '../../support/ui_fixture.dart';

final _boundary = GlobalKey();

Future<void> _open(WidgetTester t, Size size, FakeViewPadding padding) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  t.view.padding = padding;
  addTearDown(t.view.reset);
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
  await t.pumpWidget(
    ProviderScope(
      overrides: f.overrides,
      child: RepaintBoundary(
        key: _boundary,
        child: MaterialApp(
          theme: fireplaceTheme(Brightness.light),
          navigatorObservers: [chatRouteObserver],
          home: const ChatScreen(chatId: 'alice_fred', initialMessageId: '1'),
        ),
      ),
    ),
  );
  await settleUi(t);
  // Until the band has faded in, well before the highlight times out.
  for (
    var i = 0;
    i < 20 && (flashedRow('1').evaluate().isEmpty || jumpBandShown(t, '1') < 1);
    i++
  ) {
    await t.pump(const Duration(milliseconds: 50));
  }
  expect(jumpBandShown(t, '1'), 1);
}

Future<void> _expectBand(WidgetTester t, Size size) async {
  final band = t.getRect(jumpBand('1'));
  final row = t.getRect(flashedRow('1'));
  expect(band.left, 0);
  expect(band.right, size.width);
  expect(band.top, row.top);
  expect(band.height, row.height);
  // The row keeps the timeline's inset, so the bubble stays where it was.
  expect(row.left, MessageMenuMetrics.edge);
  expect(row.right, size.width - MessageMenuMetrics.edge);
  final bubble = t.getRect(find.byKey(const ValueKey('messageBubble-1')));
  expect(bubble.left, greaterThanOrEqualTo(row.left));
  expect(bubble.right, lessThanOrEqualTo(row.right));

  final decoration =
      t.widget<AnimatedContainer>(jumpBand('1')).decoration! as BoxDecoration;
  expect(decoration.borderRadius, isNull, reason: 'square corners');
  final color = decoration.color!;
  expect(color.a, 1);
  // Painted to the very edges: nothing above the band clips it.
  for (final x in [0.0, size.width - 1]) {
    final painted = await paintedPixel(t, _boundary, Offset(x, band.center.dy));
    expect(painted.toARGB32(), color.toARGB32(), reason: 'pixel at x $x');
  }
}

void main() {
  testWidgets('the band runs from edge to edge in portrait', (t) async {
    const size = Size(390, 780);
    await _open(t, size, const FakeViewPadding(top: 47, bottom: 34));
    await _expectBand(t, size);
  });

  testWidgets('in landscape it reaches past the side safe areas', (t) async {
    const size = Size(812, 375);
    await _open(
      t,
      size,
      const FakeViewPadding(left: 47, right: 47, bottom: 21),
    );
    await _expectBand(t, size);
  });

  testWidgets('only the jumped-to row is lit, and it goes', (t) async {
    await _open(t, const Size(390, 780), const FakeViewPadding(top: 47));
    expect(jumpBandShown(t, '2'), 0);
    await t.pump(TimelineScroll.flashFor);
    await t.pumpAndSettle();
    expect(jumpBandShown(t, '1'), 0);
  });
}
