// REVIEW R04: a screen reader must hear WHO sent a message. On b01a65d a bubble is announced as its time
// (label) followed by its text (value), with no sender.
import 'package:fireplace/src/ui/chat_screen.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

void main() {
  testWidgets(
    'outgoing bubbles are announced as "You", incoming ones with the contact name',
    (t) async {
      final f = UiFixture();
      await f.seed();
      addTearDown(f.session.close);
      final handle = t.ensureSemantics();
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
      String said(String id) {
        final n = t.getSemantics(find.byKey(ValueKey('messageBubble-$id')));
        return '${n.label} ${n.value}';
      }

      expect(
        said('2'),
        contains('You'),
        reason: 'message 2 is outgoing: ${said('2')}',
      );
      expect(
        said('3'),
        contains('fred'),
        reason: 'message 3 is incoming: ${said('3')}',
      );
      expect(
        said('2'),
        contains('Of course. I can bring dessert.'),
        reason: 'the text must still be read',
      );
      expect(said('3'), contains('Perfect. See you in the garden'));
      handle.dispose();
    },
  );
}
