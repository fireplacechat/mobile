import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/db/secret_store.dart';
// REVIEW R06: each swatch in Settings > Chat colors must show the colour you will actually get. On b01a65d
// the "Their messages" chips show the strong outgoing colour although incoming bubbles use the pale shade.
import 'package:fireplace/src/view/settings/chat_appearance.dart';
import 'package:fireplace/src/styles/chat_colors.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ColorBlock block(WidgetTester t, String key) =>
    t.widget<ColorBlock>(find.byKey(ValueKey(key), skipOffstage: false));
Color swatch(WidgetTester t, String key) => block(t, key).color;

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
            secretStoreProvider.overrideWithValue(MemorySecretStore()),
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
        // The whole block is the colour, with its name inside.
        for (final side in ['outgoing', 'incoming']) {
          final key = find.byKey(ValueKey('$side-${c.name}'));
          final fill = t.widget<Material>(
            find.descendant(of: key, matching: find.byType(Material)),
          );
          expect(fill.color, swatch(t, '$side-${c.name}'));
          expect(
            find.descendant(of: key, matching: find.text(c.label)),
            findsOneWidget,
          );
          expect(t.getSize(key).height, greaterThanOrEqualTo(48));
          expect(t.getSize(key).width, greaterThan(100));
        }
      }
      expect(find.byType(ChoiceChip), findsNothing);
      // Only the chosen block in each group carries the ring.
      for (final c in ChatBubbleColor.values) {
        expect(block(t, 'outgoing-${c.name}').selected, c.name == 'ember');
        expect(block(t, 'incoming-${c.name}').selected, c.name == 'stone');
      }
      Color ring(String key) =>
          ((t
                              .widget<Container>(
                                find.descendant(
                                  of: find.byKey(ValueKey(key)),
                                  matching: find.byType(Container),
                                ),
                              )
                              .decoration!
                          as BoxDecoration)
                      .border!
                  as Border)
              .top
              .color;
      expect(ring('outgoing-ember').a, 1);
      expect(ring('outgoing-ocean').a, 0);
      // Choosing moves the ring without moving the blocks.
      final before = t.getRect(find.byKey(const ValueKey('outgoing-ocean')));
      await t.tap(find.byKey(const ValueKey('outgoing-ocean')));
      await t.pump();
      expect(block(t, 'outgoing-ocean').selected, isTrue);
      expect(block(t, 'outgoing-ember').selected, isFalse);
      expect(t.getRect(find.byKey(const ValueKey('outgoing-ocean'))), before);
    });
  }
}
