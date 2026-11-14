// The bar above the composer while replying: a coloured tab, the name in the
// same colour, one line of the message and a cancel button. The colour is that
// of the person being replied to.
import 'package:fireplace/src/app/chat_color_preference.dart';
import 'package:fireplace/src/styles/chat_colors.dart';
import 'package:fireplace/src/view/chat/chat_composer.dart';
import 'package:fireplace/src/view/chat/widgets/reply_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';
import 'long_press_menu_test.dart' show openChat, bubble, action;

void main() {
  Color tab(WidgetTester t) =>
      t.widget<ColoredBox>(find.byKey(const Key('replyPanelTab'))).color;
  Color name(WidgetTester t) =>
      t.widget<Text>(find.byKey(const Key('replyPanelAuthor'))).style!.color!;
  ChatBubbleColors colors(WidgetTester t) =>
      ProviderScope.containerOf(t.element(find.byType(ChatComposer)))
          .read(chatBubbleColorsProvider);

  testWidgets('replying to them uses the colour their messages have here', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    await openChat(t, f);
    await t.longPress(bubble('5')); // from fred
    await t.pumpAndSettle();
    await t.tap(action('reply'));
    await t.pumpAndSettle();

    final panel = find.byKey(const Key('replyComposerPreview'));
    expect(t.widget(panel), isA<ReplyPanel>());
    final theirs = colors(t).incoming.accentText(Brightness.light);
    expect(tab(t), theirs);
    expect(name(t), theirs);
    expect(
      find.descendant(of: panel, matching: find.text('fred')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: panel,
        matching: find.text('Around two? There is no rush.'),
      ),
      findsOneWidget,
    );
    // The tab starts at the screen's edge and runs the height of the bar.
    expect(t.getTopLeft(find.byKey(const Key('replyPanelTab'))).dx, 0);
    expect(
      t.getSize(find.byKey(const Key('replyPanelTab'))).height,
      t.getSize(panel).height,
    );
    // One line of the message, however long it is.
    expect(
      t
          .widget<Text>(
            find.descendant(
              of: panel,
              matching: find.text('Around two? There is no rush.'),
            ),
          )
          .maxLines,
      1,
    );
    await t.tap(find.byKey(const Key('cancelReply')));
    await t.pumpAndSettle();
    expect(panel, findsNothing);
  });

  testWidgets('replying to your own message uses your primary colour', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    await f.chat.store.add(
      message(
        id: 'mine-1',
        body: 'Mine to answer',
        at: fixtureTime.add(const Duration(minutes: 5)),
        outgoing: true,
      ),
    );
    await openChat(t, f);
    await t.longPress(bubble('mine-1'));
    await t.pumpAndSettle();
    await t.tap(action('reply'));
    await t.pumpAndSettle();
    final own = colors(t).outgoing.accentText(Brightness.light);
    expect(tab(t), own);
    expect(name(t), own);
    expect(
      find.descendant(
        of: find.byKey(const Key('replyComposerPreview')),
        matching: find.text('You'),
      ),
      findsOneWidget,
    );
  });
}
