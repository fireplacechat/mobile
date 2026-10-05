// Review finding C02: while a forward is in flight the screen cannot be left (PopScope canPop:false,
// no cancel). When the phone is offline a Firestore commit does not complete, so the user is stuck on the
// screen with a back button that does nothing. They must always be able to leave; the send then resolves
// in the background / as "not confirmed". Also: "Forward to 1 chats".
import 'dart:async';

import 'package:fireplace/src/ui/forward_message.dart';
import 'package:fireplace/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/ui_fixture.dart';

Future<UiFixture> open(WidgetTester t) async {
  final f = UiFixture();
  await f.seed();
  addTearDown(f.session.close);
  await t.pumpWidget(
    ProviderScope(
      overrides: f.overrides,
      child: MaterialApp(
        theme: fireplaceTheme(Brightness.light),
        home: Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              key: const Key('open'),
              onPressed: () => Navigator.of(c).push(
                MaterialPageRoute<void>(
                  builder: (_) => ForwardMessageScreen(
                    message: message(id: '1', body: 'text', outgoing: true),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.byKey(const Key('open')));
  await settleUi(t);
  return f;
}

void main() {
  testWidgets('the user can leave while a forward send never completes', (
    t,
  ) async {
    final f = await open(t);
    f.chat.sendHold = Completer<void>(); // offline: the commit never returns
    await t.tap(find.byKey(const ValueKey('forwardRecipient-alice_bob')));
    await t.pump();
    await t.ensureVisible(find.byKey(const Key('forwardSend')));
    await t.tap(find.byKey(const Key('forwardSend')));
    await t.pump(const Duration(milliseconds: 300));
    await t.pageBack();
    await t.pumpAndSettle(); // let the exit transition finish
    expect(
      find.byType(ForwardMessageScreen),
      findsNothing,
      reason: 'back must work even while a send is pending',
    );
    f.chat.sendHold!.complete();
    await settleUi(t);
  });
  testWidgets('button text is correct for one recipient', (t) async {
    await open(t);
    await t.tap(find.byKey(const ValueKey('forwardRecipient-alice_bob')));
    await t.pump();
    expect(find.text('Forward to 1 chats'), findsNothing);
  });
}
