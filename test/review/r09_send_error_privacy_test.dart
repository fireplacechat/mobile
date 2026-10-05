// REVIEW R09: GPT's own rule is "hide internal exceptions" (auth, startup). The chat still shows
// "Could not send: <raw exception>" for unexpected errors. Phase 6 already hides that and
// uses conservative uncertain-outcome copy; keep that copy rather than promising safe retry.
import 'package:fireplace/src/ui/chat_screen.dart';
import 'package:fireplace/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/ui_fixture.dart';

void main() {
  testWidgets(
    'an unexpected send error shows plain words, never the raw exception',
    (t) async {
      final f = UiFixture();
      f.chat.sendError = StateError(
        'SECRET-INTERNAL-DETAIL /home/x/.cache/token=abc',
      );
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
      await t.enterText(find.byKey(const Key('composer')), 'hello');
      await t.pump();
      await t.tap(find.byKey(const Key('send')));
      await settleUi(t);
      expect(find.textContaining('SECRET-INTERNAL-DETAIL'), findsNothing);
      expect(find.textContaining('Bad state'), findsNothing);
      expect(
        find.textContaining('We could not confirm this send'),
        findsOneWidget,
        reason: 'the user learns the outcome is uncertain without a false resend promise',
      );
      // and the draft is kept so nothing is lost
      expect(
        t.widget<TextField>(find.byKey(const Key('composer'))).controller!.text,
        'hello',
      );
    },
  );
}
