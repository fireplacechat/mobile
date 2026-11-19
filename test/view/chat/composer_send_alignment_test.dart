// The send button sits level with the message field (issue 206): on a
// one-line message their centres line up, and the button's bottom never rides
// above the field's.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_screen_inventory_test.dart' show mount;

void main() {
  Rect field(WidgetTester t) => t.getRect(
    find
        .descendant(
          of: find.byKey(const Key('composer')),
          matching: find.byType(InputDecorator),
        )
        .first,
  );

  /// The filled circle itself, not the larger area that takes taps.
  Rect circle(WidgetTester t) => t.getRect(
    find
        .descendant(
          of: find.byKey(const Key('send')),
          matching: find.byType(Material),
        )
        .first,
  );

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('send is level with the field on ${platform.name}', (t) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      // An iPhone 11: 414 x 896 points.
      t.view.physicalSize = const Size(828, 1792);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      await mount(t, 'accepted');
      final f = field(t), c = circle(t);
      expect(c.size, const Size(40, 40));
      expect((c.center.dy - f.center.dy).abs(), lessThan(1));
      expect(c.bottom, closeTo(f.bottom, 1));
      // Still a full-size target to tap.
      expect(
        t.getSize(find.byKey(const Key('send'))).height,
        greaterThanOrEqualTo(48),
      );
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
