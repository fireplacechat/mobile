import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';
import 'long_press_menu_test.dart' show openChat, bubble, action;

void main() {
  for (final id in ['4', '5']) {
    testWidgets('held bubble $id stays aligned with its menu', (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final f = UiFixture();
      await f.seed();
      addTearDown(f.session.close);
      await openChat(t, f);
      await t.longPress(bubble(id));
      await t.pumpAndSettle();
      final held = t.getRect(find.byKey(ValueKey('heldMessage-$id')));
      final panel = t.getRect(find.byKey(const Key('messageActionsPanel')));
      expect(panel.top, greaterThanOrEqualTo(held.bottom));
      expect(
        id == '4' ? panel.right : panel.left,
        closeTo(id == '4' ? held.right : held.left, 1),
      );
      expect(panel.bottom, lessThanOrEqualTo(844 - 12));
      expect(find.byType(BackdropFilter), findsOneWidget);
      await t.tapAt(const Offset(380, 30));
      await t.pumpAndSettle();
      expect(action('copy'), findsNothing);
      expect(find.byKey(ValueKey('heldMessage-$id')), findsNothing);
    });
  }

  testWidgets('context-menu key opens actions and Escape dismisses them', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    await openChat(t, f);
    Focus.of(t.element(bubble('5'))).requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await t.pumpAndSettle();
    expect(action('copy'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(action('copy'), findsNothing);
  });
}
