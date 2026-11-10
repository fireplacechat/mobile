import 'package:fireplace/src/model/chat/chat_summary.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat/forward/forward_message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/ui_fixture.dart';

void main() {
  testWidgets('forward opens recent chats, then people, with no stories', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    f.chat.summaries = [
      ...f.chat.summaries,
      ChatSummary('alice_sam', 'sam', null),
    ];
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
    expect(find.text('Forward To'), findsOneWidget);
    expect(find.text('Stories'), findsNothing);
    expect(find.text('Recent Chats'), findsOneWidget);
    expect(find.text('People'), findsOneWidget);
    expect(
      t.getTopLeft(find.text('Recent Chats')).dy,
      lessThan(t.getTopLeft(find.text('People')).dy),
    );
    expect(
      t.getTopLeft(find.text('bob')).dy,
      lessThan(t.getTopLeft(find.text('People')).dy),
    );
    expect(
      t.getTopLeft(find.text('sam')).dy,
      greaterThan(t.getTopLeft(find.text('People')).dy),
    );
    expect(
      find.byKey(const ValueKey('forwardRecipient-alice_bob')),
      findsOneWidget,
    );
    expect(find.text('Choose a recipient'), findsOneWidget);
    expect(
      t.widget<FilledButton>(find.byKey(const Key('forwardSend'))).onPressed,
      isNull,
    );
    await t.tap(find.byKey(const ValueKey('forwardRecipient-alice_sam')));
    await t.pump();
    expect(find.text('Send to 1'), findsOneWidget);
    expect(
      t.widget<FilledButton>(find.byKey(const Key('forwardSend'))).onPressed,
      isNotNull,
    );
  });
}
