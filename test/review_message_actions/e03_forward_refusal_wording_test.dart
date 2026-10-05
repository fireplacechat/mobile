// Review finding E1 (Forward screen): any ChatException while forwarding is shown as "this chat is unavailable or at its
// request limit". A server refusal (free-plan quota used up, message too large) is a ChatException too, and the
// person must be told the real reason, in the exception's own words.
import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/ui/forward_message.dart';
import 'package:fireplace/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/ui_fixture.dart';

void main() {
  testWidgets(
    'a refusal is reported with its own reason, not as a request limit',
    (t) async {
      final f = UiFixture();
      await f.seed();
      addTearDown(f.session.close);
      f.chat.sendError = SendRefusedException(
        'The server is busy or its free usage limit has been reached, so nothing was sent. Try again later.',
      );
      await t.pumpWidget(
        ProviderScope(
          overrides: f.overrides,
          child: MaterialApp(
            theme: fireplaceTheme(Brightness.light),
            home: ForwardMessageScreen(
              message: message(id: '1', body: 'text', outgoing: true),
            ),
          ),
        ),
      );
      await settleUi(t);
      await t.tap(find.byKey(const ValueKey('forwardRecipient-alice_bob')));
      await t.pump();
      await t.ensureVisible(find.byKey(const Key('forwardSend')));
      await t.tap(find.byKey(const Key('forwardSend')));
      await settleUi(t);
      expect(find.textContaining('free usage limit'), findsOneWidget);
      expect(find.textContaining('request limit'), findsNothing);
    },
  );
}
