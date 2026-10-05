import 'package:fireplace/src/ui/logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'the mark has the approved geometry (matches the pack\'s own 1024px PNG)',
    () {
      // Expected extents measured independently from fireplace-symbol-master-1024.png.
      final b = FlamePainter.tightBounds();
      expect(b.left, closeTo(168, 2.5));
      expect(b.top, closeTo(106, 2.5));
      expect(b.right, closeTo(855, 2.5));
      expect(b.bottom, closeTo(920, 2.5));
    },
  );

  testWidgets('the logo stays burnt orange in both light and dark themes', (
    t,
  ) async {
    for (final (brightness, expected) in [
      (Brightness.light, fireplaceOrange),
      (Brightness.dark, fireplaceOrange),
    ]) {
      await t.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.light),
          darkTheme: ThemeData(brightness: Brightness.dark),
          themeMode: brightness == Brightness.dark
              ? ThemeMode.dark
              : ThemeMode.light,
          home: const Center(child: FireplaceLogo(size: 80)),
        ),
      );
      await t.pumpAndSettle(); // MaterialApp animates theme changes
      final painter =
          t
                  .widget<CustomPaint>(
                    find.descendant(
                      of: find.byType(FireplaceLogo),
                      matching: find.byType(CustomPaint),
                    ),
                  )
                  .painter!
              as FlamePainter;
      expect(painter.color, expected);
      expect(FlamePainter.master().getBounds().isEmpty, isFalse);
    }
  });
}
