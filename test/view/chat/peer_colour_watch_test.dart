// A 1:1 chat follows the other person's colour while it is open (decision
// 0064, issue 193), and stops when it closes.
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

void main() {
  testWidgets('opening a chat follows that person; closing it stops', (
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
    expect(f.chat.watchedColors, ['fred']);
    expect(f.chat.colorWatchesEnded, 0);

    await t.pumpWidget(const SizedBox());
    await settleUi(t);
    expect(f.chat.watchedColors, ['fred']);
    expect(f.chat.colorWatchesEnded, 1);
  });
}
