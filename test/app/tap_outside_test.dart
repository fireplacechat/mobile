import 'dart:async';

import 'package:fireplace/src/app.dart';
import 'package:fireplace/src/view/account/account_deletion_screens.dart';
import 'package:fireplace/src/view/auth/auth_screen.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:fireplace/src/view/chat_list/chat_list_screen.dart';
import 'package:fireplace/src/view/chat_list/start_chat_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/ui_fixture.dart';

Future<UiFixture> pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fixture = UiFixture();
  await fixture.seed();
  addTearDown(fixture.session.close);
  await tester.pumpWidget(
    ProviderScope(overrides: fixture.overrides, child: const FireplaceApp()),
  );
  await tester.pumpAndSettle();
  return fixture;
}

Future<void> openScreen(WidgetTester tester, Widget screen) async {
  unawaited(
    Navigator.of(tester.element(find.byType(AuthScreen)))
        .push<void>(MaterialPageRoute(builder: (_) => screen)),
  );
  await tester.pumpAndSettle();
}

EditableText field(WidgetTester tester, String key) =>
    tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(EditableText),
      ),
    );

void main() {
  final platforms = TargetPlatformVariant({
    TargetPlatform.android,
    TargetPlatform.iOS,
  });

  testWidgets('sign-up Next advances through fields without submitting', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('username')));
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    expect(field(tester, 'password').focusNode.hasFocus, isTrue);
    expect(field(tester, 'password').textInputAction, TextInputAction.next);
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    expect(field(tester, 'invite').focusNode.hasFocus, isTrue);
    expect(field(tester, 'invite').textInputAction, TextInputAction.done);
    expect(tester.testTextInput.isVisible, isTrue);
    expect(find.byKey(const Key('age16Error')), findsNothing);
  }, variant: platforms);

  testWidgets('account confirmation Next moves to the password field', (
    tester,
  ) async {
    await pumpApp(tester);
    await openScreen(tester, const DeleteAccountScreen());
    await tester.ensureVisible(find.byKey(const Key('confirmUsername')));
    await tester.tap(find.byKey(const Key('confirmUsername')));
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    expect(field(tester, 'confirmPassword').focusNode.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    expect(find.byKey(const Key('deleteError')), findsNothing);
  }, variant: platforms);

  testWidgets(
    'back navigation keeps separate drafts without reopening keyboard',
    (tester) async {
      await pumpApp(tester);
      await openScreen(tester, const ChatScreen(chatId: 'alice_fred'));
      await tester.enterText(find.byKey(const Key('composer')), 'For Fred');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chatBack')));
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse);
      await openScreen(tester, const ChatScreen(chatId: 'alice_bob'));
      expect(field(tester, 'composer').controller.text, isEmpty);
      await tester.enterText(find.byKey(const Key('composer')), 'For Bob');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chatBack')));
      await tester.pumpAndSettle();
      await openScreen(tester, const ChatScreen(chatId: 'alice_fred'));
      expect(field(tester, 'composer').controller.text, 'For Fred');
      expect(field(tester, 'composer').focusNode.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.tap(find.byKey(const Key('send')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chatBack')));
      await tester.pumpAndSettle();
      await openScreen(tester, const ChatScreen(chatId: 'alice_fred'));
      expect(field(tester, 'composer').controller.text, isEmpty);
    },
    variant: platforms,
  );

  for (final editDuringSend in [false, true]) {
    testWidgets(
      'leaving during send never restores attempted text (new edit: $editDuringSend)',
      (tester) async {
        final fixture = await pumpApp(tester);
        fixture.chat.sendHold = Completer<void>();
        await openScreen(tester, const ChatScreen(chatId: 'alice_fred'));
        await tester.enterText(find.byKey(const Key('composer')), 'Sending');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('send')));
        await tester.pump();
        if (editDuringSend) {
          await tester.enterText(
            find.byKey(const Key('composer')),
            'Next draft',
          );
          await tester.pump();
        }
        await tester.tap(find.byKey(const Key('chatBack')));
        await tester.pumpAndSettle();
        fixture.chat.sendHold!.complete();
        await tester.pump();
        await openScreen(tester, const ChatScreen(chatId: 'alice_fred'));
        expect(
          field(tester, 'composer').controller.text,
          editDuringSend ? 'Next draft' : '',
        );
        expect(fixture.chat.sends, ['Sending']);
      },
      variant: platforms,
    );
  }

  testWidgets(
    'chat details return to the draft without reopening the keyboard',
    (tester) async {
      await pumpApp(tester);
      await openScreen(tester, const ChatScreen(chatId: 'alice_fred'));
      await tester.enterText(
        find.byKey(const Key('composer')),
        'Keep this draft',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chatDetails')));
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(field(tester, 'composer').controller.text, 'Keep this draft');
      expect(field(tester, 'composer').focusNode.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
    },
    variant: platforms,
  );

  testWidgets('long press still opens message actions while composing', (
    tester,
  ) async {
    await pumpApp(tester);
    await openScreen(tester, const ChatScreen(chatId: 'alice_fred'));
    await tester.enterText(
      find.byKey(const Key('composer')),
      'Keep this draft',
    );
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Around two? There is no rush.'));
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Select text'), findsOneWidget);
    expect(field(tester, 'composer').controller.text, 'Keep this draft');
  }, variant: platforms);

  testWidgets('touching outside either sign-in field dismisses the keyboard', (
    tester,
  ) async {
    await pumpApp(tester);
    for (final key in ['username', 'password']) {
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
      expect(field(tester, key).focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);

      await tester.tap(find.text('Welcome back'));
      await tester.pumpAndSettle();
      expect(field(tester, key).focusNode.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
    }
  }, variant: platforms);

  testWidgets('touching outside the invite field dismisses the keyboard', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('toggle')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('invite')));
    await tester.tap(find.byKey(const Key('invite')));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(find.byKey(const Key('age16')));
    await tester.pumpAndSettle();
    expect(field(tester, 'invite').focusNode.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(
      tester.widget<CheckboxListTile>(find.byKey(const Key('age16'))).value,
      isTrue,
    );
  }, variant: platforms);

  testWidgets(
    'switching fields and revealing a password keeps editing active',
    (tester) async {
      await pumpApp(tester);
      await tester.tap(find.byKey(const Key('username')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('password')));
      await tester.pumpAndSettle();
      expect(field(tester, 'username').focusNode.hasFocus, isFalse);
      expect(field(tester, 'password').focusNode.hasFocus, isTrue);

      await tester.tap(find.byTooltip('Show password'));
      await tester.pumpAndSettle();
      expect(field(tester, 'password').obscureText, isFalse);
      expect(field(tester, 'password').focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
    },
    variant: platforms,
  );

  testWidgets(
    'search clears without losing focus and dismisses on the header',
    (tester) async {
      await pumpApp(tester);
      await openScreen(tester, const ChatListScreen());
      await tester.enterText(find.byKey(const Key('chatSearch')), 'fred');
      await tester.pump();
      await settleUi(tester);
      await tester.tap(find.byKey(const Key('clearChatSearch')));
      await tester.pumpAndSettle();
      expect(field(tester, 'chatSearch').controller.text, isEmpty);
      expect(field(tester, 'chatSearch').focusNode.hasFocus, isTrue);

      await tester.tapAt(const Offset(400, 30));
      await tester.pumpAndSettle();
      expect(field(tester, 'chatSearch').focusNode.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
    },
    variant: platforms,
  );

  testWidgets(
    'touching a conversation dismisses the keyboard and keeps draft',
    (tester) async {
      await pumpApp(tester);
      await openScreen(tester, const ChatScreen(chatId: 'alice_fred'));
      await tester.enterText(find.byKey(const Key('composer')), 'Unsent draft');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Around two? There is no rush.'));
      await tester.pumpAndSettle();
      expect(field(tester, 'composer').focusNode.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(field(tester, 'composer').controller.text, 'Unsent draft');
    },
    variant: platforms,
  );

  testWidgets('sending keeps the composer ready for the next message', (
    tester,
  ) async {
    final fixture = await pumpApp(tester);
    await openScreen(tester, const ChatScreen(chatId: 'alice_fred'));
    await tester.enterText(find.byKey(const Key('composer')), 'Hello');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('send')));
    await tester.pumpAndSettle();
    expect(fixture.chat.sends, ['Hello']);
    expect(field(tester, 'composer').controller.text, isEmpty);
    expect(field(tester, 'composer').focusNode.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
  }, variant: platforms);

  testWidgets(
    'dialog fields dismiss on outside touches without closing dialog',
    (tester) async {
      await pumpApp(tester);
      unawaited(
        showDialog<void>(
          context: tester.element(find.byType(AuthScreen)),
          builder: (_) => const StartChatDialog(),
        ),
      );
      await tester.pumpAndSettle();
      expect(field(tester, 'peerUsername').focusNode.hasFocus, isTrue);
      await tester.tap(find.text('Start a chat'));
      await tester.pumpAndSettle();
      expect(field(tester, 'peerUsername').focusNode.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(find.byType(StartChatDialog), findsOneWidget);

      await tester.tap(find.byKey(const Key('peerUsername')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(StartChatDialog), findsNothing);
      expect(tester.testTextInput.isVisible, isFalse);
    },
    variant: platforms,
  );
}
