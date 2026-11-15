// The message bar's colour reaches the bottom of the screen: on a phone with
// a home indicator, the strip under the bar is the bar's colour, not the
// conversation's.
import 'package:fireplace/src/view/chat/widgets/composer_note.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_screen_inventory_test.dart' show mount;

void main() {
  void homeIndicator(WidgetTester t) {
    t.view.padding = FakeViewPadding(bottom: 34 * t.view.devicePixelRatio);
    addTearDown(t.view.resetPadding);
  }

  testWidgets('the bar is coloured down to the bottom of the screen', (
    t,
  ) async {
    homeIndicator(t);
    await mount(t, 'accepted');
    final screen = t.view.physicalSize.height / t.view.devicePixelRatio;
    final bar = t.getRect(
      find
          .ancestor(
            of: find.byKey(const Key('composer')),
            matching: find.byType(ColoredBox),
          )
          .first,
    );
    expect(bar.bottom, screen);
    // The field itself stays clear of the home indicator.
    expect(
      t.getRect(find.byKey(const Key('composer'))).bottom,
      lessThanOrEqualTo(screen - 34),
    );
  });

  testWidgets('a note in place of the bar is coloured down to the bottom too', (
    t,
  ) async {
    homeIndicator(t);
    await mount(t, 'incoming');
    final screen = t.view.physicalSize.height / t.view.devicePixelRatio;
    final note = find.byType(ComposerNote);
    final coloured = find
        .descendant(of: note, matching: find.byType(ColoredBox))
        .first;
    expect(t.getRect(coloured).bottom, screen);
    expect(
      t.getRect(find.text('Accept this request to reply.')).bottom,
      lessThanOrEqualTo(screen - 34),
    );
  });
}
