import 'dart:async';

import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/ui/chat_screen.dart';
import 'package:fireplace/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/ui_fixture.dart';

class ActionChat extends FixtureChat {
  int checks = 0, resends = 0, saves = 0;
  Completer<SendOutcome>? checkHold;
  Completer<void>? actionHold;
  Object? checkError, saveError;
  @override
  Future<SendOutcome> checkSendStatus(String chatId, String messageId) async {
    checks++;
    if (checkError != null) throw checkError!;
    return checkHold?.future ?? Future.value(SendOutcome.confirmed);
  }

  @override
  Future<void> resendUnconfirmed({
    required String chatId,
    required String messageId,
    required String body,
  }) async {
    resends++;
    if (actionHold != null) await actionHold!.future;
  }

  @override
  Future<void> saveSentLocally({
    required String chatId,
    required String messageId,
    required String body,
    required DateTime sentAt,
  }) async {
    saves++;
    if (actionHold != null) await actionHold!.future;
    if (saveError != null) throw saveError!;
  }
}

Future<UiFixture> pending(
  WidgetTester t,
  ActionChat chat,
  SendOutcome outcome,
) async {
  final f = UiFixture(chat: chat);
  addTearDown(f.session.close);
  chat.sendError = SendNotConfirmedException(
    outcome: outcome,
    chatId: 'alice_fred',
    messageId: 'pending',
    body: 'A test message',
    attemptedAt: fixtureTime,
    persisted: false,
  );
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
  await t.enterText(find.byKey(const Key('composer')), 'A test message');
  await t.pump();
  await t.tap(find.byKey(const Key('send')));
  await settleUi(t);
  return f;
}

void main() {
  testWidgets(
    'confirmed server message with failed local repair cannot offer resend',
    (t) async {
      final c = ActionChat()
        ..saveError = StateError('private storage diagnostics');
      await pending(t, c, SendOutcome.publishUnknown);
      await t.tap(find.byKey(const Key('checkSendStatus')));
      await settleUi(t);
      expect(find.text('Sent — could not save on this device'), findsOneWidget);
      expect(find.byKey(const Key('resendUnconfirmed')), findsNothing);
      expect(c.saves, 1);
      expect(c.resends, 0);
      await t.tap(find.byKey(const Key('saveOnDevice')));
      await settleUi(t);
      expect(
        find.textContaining('Could not save on this device yet.'),
        findsOneWidget,
      );
      expect(find.textContaining('private storage diagnostics'), findsNothing);
    },
  );
  testWidgets('checking suppresses repeats and blocks concurrent resend', (
    t,
  ) async {
    final c = ActionChat()..checkHold = Completer<SendOutcome>();
    await pending(t, c, SendOutcome.publishUnknown);
    final callback = t
        .widget<TextButton>(find.byKey(const Key('checkSendStatus')))
        .onPressed!;
    callback();
    callback();
    await t.pump();
    expect(c.checks, 1);
    expect(
      t
          .widget<TextButton>(find.byKey(const Key('resendUnconfirmed')))
          .onPressed,
      isNull,
    );
    c.checkHold!.complete(SendOutcome.publishUnknown);
    await settleUi(t);
    expect(find.text('Message not confirmed'), findsOneWidget);
  });
  testWidgets(
    'resend has one confirmation and one explicit publication while pending',
    (t) async {
      final c = ActionChat()..actionHold = Completer<void>();
      await pending(t, c, SendOutcome.publishUnknown);
      final callback = t
          .widget<TextButton>(find.byKey(const Key('resendUnconfirmed')))
          .onPressed!;
      callback();
      callback();
      await t.pumpAndSettle();
      expect(find.text('Send another copy?'), findsOneWidget);
      await t.tap(find.byKey(const Key('confirmResend')));
      await t.pumpAndSettle();
      expect(c.resends, 1);
      expect(
        t
            .widget<TextButton>(find.byKey(const Key('resendUnconfirmed')))
            .onPressed,
        isNull,
      );
      c.actionHold!.complete();
      await settleUi(t);
      expect(find.text('Message not confirmed'), findsNothing);
    },
  );
  testWidgets(
    'local save is single flight and completing after navigation is safe',
    (t) async {
      final c = ActionChat()..actionHold = Completer<void>();
      await pending(t, c, SendOutcome.publishedLocalSaveFailed);
      final callback = t
          .widget<TextButton>(find.byKey(const Key('saveOnDevice')))
          .onPressed!;
      callback();
      callback();
      await t.pump();
      expect(c.saves, 1);
      expect(c.resends, 0);
      await t.pumpWidget(const SizedBox());
      c.actionHold!.complete();
      await t.pump();
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'check failures retain warning without diagnostic detail or another publication',
    (t) async {
      final c = ActionChat()..checkError = StateError('private server detail');
      await pending(t, c, SendOutcome.publishUnknown);
      await t.tap(find.byKey(const Key('checkSendStatus')));
      await settleUi(t);
      expect(find.textContaining('Could not check yet.'), findsOneWidget);
      expect(find.textContaining('private server detail'), findsNothing);
      expect(c.resends, 0);
    },
  );
}
