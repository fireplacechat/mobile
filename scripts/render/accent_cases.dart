// The same screens with a saved chat colour other than the default, to show
// that it is the app's primary colour: avatars, counts, buttons, sent
// messages and the outline of a text box being typed in.
// All names and messages here are fictional.
import 'package:fireplace/src/app/chat_color_preference.dart';
import 'package:fireplace/src/view/auth/auth_screen.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:fireplace/src/view/chat_list/chat_list_screen.dart';
import 'package:fireplace/src/view/settings/chat_appearance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/support/ui_fixture.dart';
import 'catalog_case.dart';
import 'reference_cases.dart';

/// What an earlier run of the app would have saved on the device.
void _saved(UiFixture f, String colors) =>
    f.secrets.data[ChatAppearance.storageKey] = colors;

/// Focus the field and let its outline finish appearing.
Future<void> _focus(WidgetTester t, Finder field) async {
  await t.tap(field);
  await settleUi(t);
  await t.pump(const Duration(milliseconds: 400));
}

Future<void> _history(UiFixture f) async {
  for (var i = 0; i < 40; i++) {
    await f.chat.store.add(
      message(
        id: 'history-$i',
        body: i.isEven
            ? 'A note about the weekend plan, number $i.'
            : 'Sounds good to me.',
        outgoing: i.isOdd,
        at: fixtureTime.add(Duration(minutes: i + 1)),
      ),
    );
  }
}

final accentCases = <CatalogCase>[
  for (final color in ['ocean', 'forest', 'plum'])
    CatalogCase(
      'accent-$color-chat-list',
      const ChatListScreen(),
      prepare: (f) {
        _saved(f, '$color,stone');
        seedReferenceChats(f);
      },
    ),
  CatalogCase(
    'accent-ocean-chat-colors',
    const ChatAppearanceScreen(),
    prepare: (f) => _saved(f, 'ocean,forest'),
  ),
  CatalogCase(
    'accent-ocean-search-typing',
    const ChatListScreen(),
    prepare: (f) => _saved(f, 'ocean,stone'),
    act: (t, f) => _focus(t, find.byKey(const Key('chatSearch'))),
  ),
  CatalogCase(
    'accent-ocean-conversation-typing',
    const ChatScreen(chatId: 'alice_fred'),
    prepare: (f) => _saved(f, 'ocean,stone'),
    interaction: CatalogInteraction.compose,
    act: (t, f) => _focus(t, find.byKey(const Key('composer'))),
  ),
  CatalogCase(
    'accent-ocean-latest-messages',
    const ChatScreen(chatId: 'alice_fred'),
    prepare: (f) => _saved(f, 'ocean,stone'),
    act: (t, f) async {
      await _history(f);
      await settleUi(t);
      t
          .widget<ListView>(find.byKey(const Key('messageTimeline')))
          .controller!
          .jumpTo(500);
      await settleUi(t);
    },
  ),
  CatalogCase(
    'accent-ocean-sign-in-typing',
    const AuthScreen(),
    prepare: (f) => _saved(f, 'ocean,stone'),
    act: (t, f) => _focus(t, find.byType(TextField).first),
  ),
];
