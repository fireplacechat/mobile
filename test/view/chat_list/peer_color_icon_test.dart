// In an accepted 1:1 chat the other person's avatar is filled with their
// colour and their name is written in it (decision 0053); before the chat is
// accepted, and while their colour is not known, both look as before.
import 'package:fireplace/src/app/chat_color_preference.dart';
import 'package:fireplace/src/model/chat/chat_summary.dart';
import 'package:fireplace/src/styles/chat_colors.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat/chat_app_bar_parts.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:fireplace/src/view/chat_list/chat_list_screen.dart';
import 'package:fireplace/src/widgets/avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

void main() {
  Future<void> pump(WidgetTester t, UiFixture f, Widget home) async {
    addTearDown(f.session.close);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          ...f.overrides,
          for (final peer in ['fred', 'bob', 'dora'])
            knownPeerColorProvider(peer).overrideWithValue(
              // Bob's profile names no colour.
              peer == 'bob' ? null : ChatBubbleColor.plum,
            ),
        ],
        child: MaterialApp(theme: fireplaceTheme(Brightness.light), home: home),
      ),
    );
    await settleUi(t);
  }

  Color? avatarFill(WidgetTester t, Finder within) => t
      .widget<PersonAvatar>(
        find.descendant(of: within, matching: find.byType(PersonAvatar)),
      )
      .color;
  Color nameColor(WidgetTester t, Finder within, String name) => t
      .widget<Text>(find.descendant(of: within, matching: find.text(name)))
      .style!
      .color!;

  testWidgets('the chat list shows an accepted person in their colour', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    // Dora has not accepted the chat this account started.
    f.chat.summaries = [
      ...f.chat.summaries,
      ChatSummary(
        'alice_dora',
        'dora',
        fixtureTime,
        initiator: 'alice',
        accepted: false,
      ),
    ];
    await pump(t, f, const ChatListScreen());
    final text = FireplaceUiTokens.of(t.element(find.byType(Scaffold).first));
    final fred = find.byKey(const ValueKey('conversation-alice_fred'));
    final bob = find.byKey(const ValueKey('conversation-alice_bob'));
    final dora = find.byKey(const ValueKey('conversation-alice_dora'));

    expect(avatarFill(t, fred), ChatBubbleColor.plum.outgoing);
    expect(
      nameColor(t, fred, 'fred'),
      ChatBubbleColor.plum.accentText(Brightness.light),
    );
    // No colour on the profile: the usual look.
    expect(avatarFill(t, bob), isNull);
    expect(nameColor(t, bob, 'bob'), text.text);
    // A colour is known, but the chat is not accepted yet.
    expect(avatarFill(t, dora), isNull);
    expect(nameColor(t, dora, 'dora'), text.text);
  });

  testWidgets('the top of a conversation shows them in their colour', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    await pump(t, f, const ChatScreen(chatId: 'alice_fred'));
    final title = find.byType(ChatTitle);
    expect(avatarFill(t, title), ChatBubbleColor.plum.outgoing);
    expect(
      nameColor(t, title, 'fred'),
      ChatBubbleColor.plum.accentText(Brightness.light),
    );
  });
}
