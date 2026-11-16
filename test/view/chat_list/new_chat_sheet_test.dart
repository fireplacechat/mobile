// The New chat panel: To: field, Create group, and the people you chat with.
import 'package:fireplace/src/app/group_providers.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:fireplace/src/view/chat_list/chat_list_screen.dart';
import 'package:fireplace/src/view/chat_list/new_chat_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

Future<UiFixture> pumpList(WidgetTester t) async {
  final f = UiFixture();
  await f.seed();
  addTearDown(f.session.close);
  await t.pumpWidget(
    ProviderScope(
      overrides: f.overrides,
      child: MaterialApp(
        theme: fireplaceTheme(Brightness.dark),
        home: const ChatListScreen(),
      ),
    ),
  );
  await settleUi(t);
  await t.tap(find.byKey(const Key('newChat')));
  await t.pumpAndSettle();
  return f;
}

void main() {
  testWidgets('lists the people you chat with, but not incoming requests', (
    t,
  ) async {
    await pumpList(t);
    expect(find.byType(NewChatSheet), findsOneWidget);
    expect(find.text('New chat'), findsOneWidget);
    expect(find.byKey(const Key('contact_fred')), findsOneWidget);
    expect(find.byKey(const Key('contact_bob')), findsOneWidget);
    // Theo's request waits in Message requests, not here.
    expect(find.byKey(const Key('contact_theo')), findsNothing);
    // No group service in this build: no Create group row.
    expect(find.byKey(const Key('newGroup')), findsNothing);
  });

  testWidgets('tapping a person opens your chat with them', (t) async {
    final f = await pumpList(t);
    await t.tap(find.byKey(const Key('contact_bob')));
    await t.pumpAndSettle();
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(f.chat.starts, isEmpty);
  });

  testWidgets('typing filters, and a new username can be messaged', (t) async {
    final f = await pumpList(t);
    await t.enterText(find.byKey(const Key('peerUsername')), 'fr');
    await t.pump();
    expect(find.byKey(const Key('contact_fred')), findsOneWidget);
    expect(find.byKey(const Key('contact_bob')), findsNothing);
    // "fr" is too short to be a username.
    expect(find.byKey(const Key('startChat')), findsNothing);

    await t.enterText(find.byKey(const Key('peerUsername')), 'fred');
    await t.pump();
    // An existing contact: no second "Message" row.
    expect(find.byKey(const Key('startChat')), findsNothing);

    await t.enterText(find.byKey(const Key('peerUsername')), 'mira_k');
    await t.pump();
    expect(find.text('Message @mira_k'), findsOneWidget);
    await t.tap(find.byKey(const Key('startChat')));
    await t.pumpAndSettle();
    expect(f.chat.starts, ['mira_k']);
  });

  testWidgets('the x in the corner closes the panel', (t) async {
    await pumpList(t);
    // A round button with an x, at the right; no word "Cancel".
    final close = find.byKey(const Key('cancelNewChat'));
    expect(t.widget(close), isA<IconButton>());
    expect(find.text('Cancel'), findsNothing);
    expect(
      t.getCenter(close).dx,
      greaterThan(t.getCenter(find.text('New chat')).dx),
    );
    await t.tap(close);
    await t.pumpAndSettle();
    expect(find.byType(NewChatSheet), findsNothing);
  });

  testWidgets('the To field is a pill, in the search field\'s text, and '
      'outlined in red for a name that cannot be messaged', (t) async {
    await pumpList(t);
    final field = find.byKey(const Key('peerUsername'));
    InputDecoration decoration() => t.widget<TextField>(field).decoration!;
    for (final border in [
      decoration().enabledBorder,
      decoration().errorBorder,
      decoration().focusedErrorBorder,
    ]) {
      expect(
        (border! as OutlineInputBorder).borderRadius,
        BorderRadius.circular(999),
      );
    }
    expect(t.widget<TextField>(field).style!.fontSize, 16);
    // "To:" has room on its left.
    expect(
      t.getTopLeft(find.text('To:')).dx - t.getTopLeft(field).dx,
      greaterThanOrEqualTo(16),
    );
    expect(decoration().errorText, isNull);
    await t.enterText(field, 'no such name');
    await t.testTextInput.receiveAction(TextInputAction.go);
    await t.pump();
    expect(decoration().errorText, isNotNull);
    expect(
      (decoration().errorBorder! as OutlineInputBorder).borderSide.width,
      2,
    );
  });

  testWidgets('every checkbox in the app is round', (t) async {
    for (final brightness in Brightness.values) {
      expect(
        fireplaceTheme(brightness).checkboxTheme.shape,
        isA<CircleBorder>(),
      );
    }
  });

  testWidgets('Create group shows when groups are on', (t) async {
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    await t.pumpWidget(
      ProviderScope(
        overrides: [...f.overrides, groupsOnProvider.overrideWithValue(true)],
        child: MaterialApp(
          theme: fireplaceTheme(Brightness.dark),
          home: const ChatListScreen(),
        ),
      ),
    );
    await settleUi(t);
    await t.tap(find.byKey(const Key('newChat')));
    await t.pumpAndSettle();
    expect(find.text('Create group'), findsOneWidget);
  });
}
