// Issue 245: at the top of a 1:1 chat, the avatar and the name open the
// person's profile; the space beside the name does not.
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:fireplace/src/view/profile/person_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

void main() {
  testWidgets('the avatar and the name open the profile, nothing else does', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    await t.pumpWidget(
      ProviderScope(
        overrides: f.overrides,
        child: MaterialApp(
          theme: fireplaceTheme(Brightness.light),
          home: const ChatScreen(chatId: 'alice_fred'),
        ),
      ),
    );
    await settleUi(t);
    for (final part in ['chatAvatar', 'chatDetails']) {
      await t.tap(find.byKey(Key(part)));
      await t.pumpAndSettle();
      expect(find.byType(PersonProfileScreen), findsOneWidget, reason: part);
      await t.pageBack();
      await t.pumpAndSettle();
    }
    // The name's tap area hugs the word: the bar beside it is not a button.
    final name = t.getRect(find.byKey(const Key('chatDetails')));
    await t.tapAt(Offset(name.right + 40, name.center.dy));
    await t.pumpAndSettle();
    expect(find.byType(PersonProfileScreen), findsNothing);
    expect(name.width, lessThan(120));
  });
}
