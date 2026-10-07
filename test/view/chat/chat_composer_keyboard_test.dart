import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_screen_inventory_test.dart' show mount;

void main() {
  testWidgets(
    'long draft keeps the parent keyboard inset for composer sizing',
    (t) async {
      await mount(t, 'large text keyboard');
      final composer = find.byKey(const Key('composer'));
      await t.enterText(composer, 'A long draft. ' * 40);
      await t.pump();
      expect(t.widget<TextField>(composer).maxLines, 3);
      final constraint = t.widget<ConstrainedBox>(
        find
            .ancestor(of: composer, matching: find.byType(ConstrainedBox))
            .first,
      );
      expect(constraint.constraints.maxHeight, 120);
      expect(t.takeException(), isNull);
    },
  );
}
