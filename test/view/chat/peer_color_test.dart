// In a 1:1 chat the other person's messages, and a reply to them, use the
// colour that person chose (decision 0052); before it has arrived, the default.
import 'package:fireplace/src/app/chat_color_preference.dart';
import 'package:fireplace/src/styles/chat_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';
import 'long_press_menu_test.dart' show openChat, bubble, action;

void main() {
  Color fill(WidgetTester t, String id) =>
      (t
                  .widget<Container>(find.byKey(ValueKey('messageBubble-$id')))
                  .decoration!
              as BoxDecoration)
          .color!;

  testWidgets('their bubbles and a reply to them use their colour', (t) async {
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    await openChat(
      t,
      f,
      overrides: [
        peerColorProvider('fred').overrideWithValue(ChatBubbleColor.plum),
      ],
    );
    expect(fill(t, '5'), ChatBubbleColor.plum.incoming(Brightness.light));
    await t.longPress(bubble('5'));
    await t.pumpAndSettle();
    await t.tap(action('reply'));
    await t.pumpAndSettle();
    final plum = ChatBubbleColor.plum.accentText(Brightness.light);
    expect(
      t.widget<ColoredBox>(find.byKey(const Key('replyPanelTab'))).color,
      plum,
    );
    expect(
      t.widget<Text>(find.byKey(const Key('replyPanelAuthor'))).style!.color,
      plum,
    );
  });

  testWidgets('before their colour arrives, their bubbles use the default', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    await openChat(t, f);
    expect(fill(t, '5'), ChatBubbleColors.unknown.incoming(Brightness.light));
  });
}
