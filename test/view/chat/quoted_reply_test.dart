import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/providers.dart';

import '../../support/ui_fixture.dart';
import 'long_press_menu_test.dart' show openChat, bubble, action;

void main() {
  testWidgets('reply preview cancels without changing the ordinary draft', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    await openChat(t, f);
    await t.enterText(find.byKey(const Key('composer')), 'Unsent draft');
    await t.longPress(bubble('5'));
    await t.pumpAndSettle();
    await t.tap(action('reply'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('replyComposerPreview')), findsOneWidget);
    expect(
      t
          .widget<TextField>(find.byKey(const Key('composer')))
          .focusNode!
          .hasFocus,
      isTrue,
    );
    await t.tap(find.byKey(const Key('cancelReply')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('replyComposerPreview')), findsNothing);
    expect(find.text('Unsent draft'), findsOneWidget);
  });
  testWidgets(
    'swipe right replies, sends a quote and taps back to the original',
    (t) async {
      final f = UiFixture();
      await f.seed();
      addTearDown(f.session.close);
      await openChat(t, f);
      await t.drag(bubble('5'), const Offset(90, 0));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('replyComposerPreview')), findsOneWidget);
      await t.enterText(find.byKey(const Key('composer')), 'Two works for me');
      await t.pump();
      await t.tap(find.byKey(const Key('send')));
      await t.pumpAndSettle();
      expect(f.chat.replies, [('5', 'Two works for me')]);
      expect(find.byKey(const Key('replyComposerPreview')), findsNothing);
      final quote = find.byKey(const ValueKey('messageQuote-reply-1'));
      expect(quote, findsOneWidget);
      await t.tap(quote);
      await t.pumpAndSettle();
      expect(bubble('5'), findsOneWidget);
      expect(bubble('reply-1'), findsNothing);
    },
  );
  testWidgets(
    'short or left swipe does not reply; access change clears the preview',
    (t) async {
      final f = UiFixture();
      await f.seed();
      addTearDown(f.session.close);
      await openChat(t, f);
      await t.drag(bubble('5'), const Offset(-80, 0));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('replyComposerPreview')), findsNothing);
      await t.drag(bubble('5'), const Offset(90, 0));
      await t.pumpAndSettle();
      f.blocked = {'fred'};
      ProviderScope.containerOf(t.element(find.byKey(const Key('composer'))))
          .invalidate(blockedUidsProvider);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('replyComposerPreview')), findsNothing);
    },
  );
}
