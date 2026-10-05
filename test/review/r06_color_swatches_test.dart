import 'package:fireplace/src/app/providers.dart';
// REVIEW R06: each swatch in Settings > Chat colors must show the colour you will actually get. On b01a65d
// the "Their messages" chips show the strong outgoing colour although incoming bubbles use the pale shade.
import 'package:fireplace/src/ui/chat_appearance.dart';
import 'package:fireplace/src/ui/chat_colors.dart';
import 'package:fireplace/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Color swatch(WidgetTester t, String key) => t
    .widget<CircleAvatar>(
      find.descendant(
        of: find.byKey(ValueKey(key), skipOffstage: false),
        matching: find.byType(CircleAvatar),
      ),
    )
    .backgroundColor!;

void main() {
  for (final b in [Brightness.light, Brightness.dark]) {
    testWidgets('swatches match the bubbles they select (${b.name})', (
      t,
    ) async {
      t.view.physicalSize = const Size(800, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            authUserProvider.overrideWithValue(const AsyncData(null)),
          ],
          child: MaterialApp(
            theme: fireplaceTheme(b),
            home: const ChatAppearanceScreen(),
          ),
        ),
      );
      await t.pump();
      for (final c in ChatBubbleColor.values) {
        expect(
          swatch(t, 'outgoing-${c.name}'),
          c.outgoing,
          reason: 'outgoing ${c.label}',
        );
        expect(
          swatch(t, 'incoming-${c.name}'),
          c.incoming(b),
          reason: 'incoming ${c.label} must show the bubble colour',
        );
      }
    });
  }
}
