// Settings > Your color: one colour to choose, and a preview of how your
// messages look to you and to other people (decision 0052).
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/db/secret_store.dart';
import 'package:fireplace/src/styles/chat_colors.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/settings/chat_appearance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('the preview shows what you see and what they see '
        '(${brightness.name})', (t) async {
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            authUserProvider.overrideWithValue(const AsyncData(null)),
            secretStoreProvider.overrideWithValue(MemorySecretStore()),
          ],
          child: MaterialApp(
            theme: fireplaceTheme(brightness),
            home: const ChatAppearanceScreen(),
          ),
        ),
      );
      await t.pump();
      Color fill(String key) =>
          (t
                      .widget<Container>(
                        find.descendant(
                          of: find.byKey(Key(key)),
                          matching: find.byType(Container),
                        ),
                      )
                      .decoration!
                  as BoxDecoration)
              .color!;
      expect(
        find.text(
          'Choose colors for your messages in all chats. Your color is also '
          'used for avatars, buttons, and assets within the app.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Applies to all chats. Your choice is kept on this device. It is '
          'also encrypted in your messages, the server never sees it.',
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('theySeePreview')),
          matching: find.text('They see'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('youSeePreview')),
          matching: find.text('You see'),
        ),
        findsOneWidget,
      );
      // The default colour, then a chosen one: both bubbles follow it.
      expect(fill('youSeePreview'), ChatBubbleColor.ember.outgoing);
      expect(
        fill('theySeePreview'),
        ChatBubbleColor.ember.incoming(brightness),
      );
      await t.ensureVisible(find.byKey(const ValueKey('outgoing-plum')));
      await t.tap(find.byKey(const ValueKey('outgoing-plum')));
      await t.pump();
      expect(fill('youSeePreview'), ChatBubbleColor.plum.outgoing);
      expect(fill('theySeePreview'), ChatBubbleColor.plum.incoming(brightness));
      // One colour only: nothing chooses other people's.
      expect(find.text('Their messages'), findsNothing);
      expect(find.byKey(const ValueKey('incoming-plum')), findsNothing);
    });
  }
}
