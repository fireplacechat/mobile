import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/src/view/chat/message_press.dart';

import 'long_press_menu_test.dart' show action, bubble, openChat;
import '../../support/ui_fixture.dart';

/// Scale of each copy of the bubble. Focus draws a second one. The shrink is
/// the ancestor transform; a reply drag on the same bubble does not scale it.
Iterable<double> scalesOf(WidgetTester t, String id) sync* {
  for (final name in ['messageBubble-$id', 'heldMessage-$id']) {
    final target = find.byKey(ValueKey(name));
    if (target.evaluate().isEmpty) continue;
    final scales = t
        .widgetList<Transform>(
          find.ancestor(of: target, matching: find.byType(Transform)),
        )
        .map((transform) => transform.transform.entry(0, 0));
    expect(scales, isNotEmpty);
    yield scales.reduce(min);
  }
}

double scaleOf(WidgetTester t, String id) {
  final scales = scalesOf(t, id).toList();
  expect(scales, hasLength(1));
  return scales.single;
}

void main() {
  testWidgets('a short press does nothing; the shrink finishes into the menu', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    await openChat(t, f);

    final center = t.getCenter(bubble('5'));
    final brief = await t.startGesture(center);
    await t.pump(const Duration(milliseconds: 100));
    await brief.up();
    await t.pump(messagePressShrink);
    expect(action('reply'), findsNothing);
    expect(scaleOf(t, '5'), 1);

    final shrinking = await t.startGesture(center);
    await t.pump(messagePressRecognize);
    await t.pump(const Duration(milliseconds: 100));
    expect(scaleOf(t, '5'), lessThan(1));
    expect(scaleOf(t, '5'), greaterThan(messagePressScale));
    expect(action('reply'), findsNothing);
    await shrinking.up();
    await t.pump();
    await t.pump(messagePressShrink);
    expect(action('reply'), findsNothing);
    expect(scaleOf(t, '5'), closeTo(1, 0.001));

    final held = await t.startGesture(center);
    await t.pump(messagePressRecognize);
    await t.pump(messagePressShrink);
    expect(action('reply'), findsOneWidget);
    expect(scalesOf(t, '5'), everyElement(1));
    await held.up();
    await t.pumpAndSettle();
  });
}
