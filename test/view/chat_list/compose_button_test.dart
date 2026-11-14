import 'package:fireplace/src/styles/chat_colors.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat_list/chat_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final accent in [ChatBubbleColor.ember, ChatBubbleColor.ocean]) {
      testWidgets('round compose, narrow large text: $brightness $accent', (
        t,
      ) async {
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final semantics = t.ensureSemantics();
        try {
          final f = UiFixture();
          await f.seed();
          addTearDown(f.session.close);
          final theme = fireplaceTheme(brightness, accent: accent);
          await t.pumpWidget(
            ProviderScope(
              overrides: f.overrides,
              child: MaterialApp(
                theme: theme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(2)),
                  child: child!,
                ),
                home: const ChatListScreen(),
              ),
            ),
          );
          await settleUi(t);
          final button = find.byKey(const Key('newChat'));
          final fab = t.widget<FloatingActionButton>(button);
          expect(fab.isExtended, isFalse);
          expect(fab.shape, const CircleBorder());
          expect(fab.tooltip, 'New chat');
          expect(t.getSize(button), const Size.square(50));
          expect(find.text('New chat'), findsNothing);
          expect(find.bySemanticsLabel('New chat'), findsOneWidget);
          expect(
            theme.floatingActionButtonTheme.backgroundColor,
            accent.outgoing,
          );
          expect(t.takeException(), isNull);
          await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(t, meetsGuideline(androidTapTargetGuideline));

          await t.tap(button);
          await t.pumpAndSettle();
          expect(find.byKey(const Key('peerUsername')), findsOneWidget);
          await t.enterText(find.byKey(const Key('peerUsername')), 'mira_k');
          await t.pump();
          await t.tap(find.byKey(const Key('startChat')));
          await t.pumpAndSettle();
          expect(f.chat.starts, ['mira_k']);
        } finally {
          semantics.dispose();
        }
      });
    }
  }
}
