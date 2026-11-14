import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat_list/chat_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

void main() {
  testWidgets(
    'opening another account chat list cannot erase history with a deleted contact',
    (t) async {
      final fixture = UiFixture();
      await t.runAsync(fixture.seed);
      fixture.names['fred'] = Future.value(deletedAccountLabel);
      final before = await t.runAsync(
        () => fixture.chat.store.watch('alice_fred').first,
      );
      expect(before, isNotEmpty);
      var cleanups = 0;
      addTearDown(fixture.session.close);
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            ...fixture.overrides,
            peerDeletedCleanupProvider.overrideWith((ref, chatId) async {
              cleanups++;
              await fixture.chat.store.deleteChat(chatId);
              return true;
            }),
          ],
          child: MaterialApp(
            theme: fireplaceTheme(Brightness.light),
            home: const ChatListScreen(),
          ),
        ),
      );
      await settleUi(t);
      expect(find.text(deletedAccountLabel), findsOneWidget);
      expect(cleanups, 0);
      expect(
        await t.runAsync(() => fixture.chat.store.watch('alice_fred').first),
        before,
      );
    },
  );
}
