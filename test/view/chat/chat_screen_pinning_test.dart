import 'dart:async';

import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/model/chat/pending_sends.dart';
import 'package:fireplace/src/model/settings/local_chat_preferences.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/ui/chat_activity.dart';
import 'package:fireplace/src/ui/chat_screen.dart';
import 'package:fireplace/src/view/chat/widgets/message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';
import 'send_action_feedback_test.dart' show ActionChat, pending;

class PinningChat extends ActionChat {
  Object? resendError;
  @override
  Future<void> acceptRequest(String chatId) async => throw StateError('accept');
  @override
  Future<void> resendUnconfirmed({
    required String chatId,
    required String messageId,
    required String body,
  }) async {
    await super.resendUnconfirmed(
      chatId: chatId,
      messageId: messageId,
      body: body,
    );
    if (resendError != null) throw resendError!;
  }
}

class FailingReviewKeys extends FixtureKeys {
  @override
  Future<List<int>?> pinnedIdentity(String peerUid) async =>
      throw StateError('review');
}

Future<void> host(
  WidgetTester t,
  UiFixture f, {
  String? initialMessageId,
  bool reducedMotion = false,
}) async {
  addTearDown(f.session.close);
  await t.pumpWidget(
    ProviderScope(
      overrides: f.overrides,
      child: MaterialApp(
        navigatorObservers: [chatRouteObserver],
        theme: fireplaceTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: reducedMotion),
          child: child!,
        ),
        home: ChatScreen(
          chatId: 'alice_fred',
          initialMessageId: initialMessageId,
        ),
      ),
    ),
  );
  await settleUi(t);
}

Future<void> send(WidgetTester t) async {
  await t.enterText(find.byKey(const Key('composer')), 'hello');
  await t.pump();
  await t.tap(find.byKey(const Key('send')));
  await settleUi(t);
}

void main() {
  testWidgets(
    'pending identity blocks a captured send action without publishing',
    (t) async {
      final f = UiFixture();
      await host(t, f);
      await t.enterText(find.byKey(const Key('composer')), 'hello');
      await t.pump();
      final action = t
          .widget<IconButton>(find.byKey(const Key('send')))
          .onPressed!;
      f.alerts['fred'] = List.filled(64, 7);
      action();
      await settleUi(t);
      expect(
        find.text('Review the security code change before sending.'),
        findsOneWidget,
      );
      expect(f.chat.sends, isEmpty);
    },
  );
  testWidgets('identity exception from send opens security review', (t) async {
    final f = UiFixture()
      ..chat.sendError = IdentityChangedException('fred', List.filled(64, 7));
    await host(t, f);
    await send(t);
    expect(find.text('Security code changed'), findsOneWidget);
    await t.ensureVisible(find.byKey(const Key('keepBlocked')));
    await t.pump();
    await t.tap(find.byKey(const Key('keepBlocked')));
    await settleUi(t);
    expect(
      t.widget<TextField>(find.byKey(const Key('composer'))).controller!.text,
      'hello',
    );
  });
  testWidgets(
    'confirmed check and successful local repair forget the warning',
    (t) async {
      final c = ActionChat();
      final f = await pending(t, c, SendOutcome.publishUnknown);
      await t.tap(find.byKey(const Key('checkSendStatus')));
      await settleUi(t);
      expect(c.saves, 1);
      expect(find.text('Message not confirmed'), findsNothing);
      expect(
        find.text('Message confirmed: it reached the server.'),
        findsOneWidget,
      );
      final container = ProviderScope.containerOf(
        t.element(find.byType(ChatScreen)),
      );
      expect(container.read(pendingLocalSendsProvider), isEmpty);
      expect(f.chat.sends, hasLength(1));
    },
  );
  for (final (label, error, expected) in [
    (
      'unknown',
      SendNotConfirmedException(
        outcome: SendOutcome.publishUnknown,
        chatId: 'alice_fred',
        messageId: 'new-copy',
        body: 'new copy',
        attemptedAt: fixtureTime,
        persisted: false,
      ),
      'Message not confirmed',
    ),
    ('refused', ChatException('Copy refused'), 'Copy refused'),
    (
      'other',
      StateError('private detail'),
      'The new copy is not confirmed. It may have reached them. Do not send another copy without checking.',
    ),
  ]) {
    testWidgets('resend $label failure preserves the appropriate warning', (
      t,
    ) async {
      final c = PinningChat()..resendError = error;
      await pending(t, c, SendOutcome.publishUnknown);
      await t.tap(find.byKey(const Key('resendUnconfirmed')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('confirmResend')));
      await settleUi(t);
      expect(
        find.text(expected),
        label == 'unknown' ? findsWidgets : findsOneWidget,
      );
      expect(c.resends, 1);
      if (label == 'unknown') {
        final container = ProviderScope.containerOf(
          t.element(find.byType(ChatScreen)),
        );
        expect(
          container
              .read(pendingLocalSendsProvider)
              .values
              .any((e) => e.messageId == 'new-copy'),
          isTrue,
        );
      }
    });
  }
  testWidgets('contact action failure has safe feedback and clears busy', (
    t,
  ) async {
    final c = PinningChat()
      ..summaries = [
        ChatSummary(
          'alice_fred',
          'fred',
          fixtureTime,
          initiator: 'fred',
          accepted: false,
        ),
      ];
    await host(t, UiFixture(chat: c));
    await t.ensureVisible(find.byKey(const Key('acceptRequest')));
    await t.tap(find.byKey(const Key('acceptRequest')));
    await settleUi(t);
    expect(
      find.text('Could not update this contact. Try again.'),
      findsOneWidget,
    );
    expect(
      t.widget<FilledButton>(find.byKey(const Key('acceptRequest'))).onPressed,
      isNotNull,
    );
  });
  testWidgets('security review failure has safe feedback and clears guard', (
    t,
  ) async {
    final f = UiFixture(keys: FailingReviewKeys())
      ..alerts = {'fred': List.filled(64, 7)};
    await host(t, f);
    await t.ensureVisible(find.byKey(const Key('reviewIdentity')));
    await t.tap(find.byKey(const Key('reviewIdentity')));
    await settleUi(t);
    expect(
      find.textContaining('Could not finish the security review.'),
      findsOneWidget,
    );
  });
  testWidgets('unread persistence failure shows feedback without escaping', (
    t,
  ) async {
    final prefs = LocalChatPreferences(
      save: (_) async => throw StateError('save'),
    );
    final f = UiFixture(chatPreferences: prefs);
    await f.seed();
    await host(t, f);
    final dynamic state = t.state(find.byType(ChatScreen));
    state.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await settleUi(t);
    expect(
      find.text('Could not save the unread count on this device.'),
      findsOneWidget,
    );
    expect(t.takeException(), isNull);
  });
  testWidgets('mute persistence failure shows feedback', (t) async {
    final f = UiFixture(
      chatPreferences: LocalChatPreferences(
        save: (_) async => throw StateError('mute'),
      ),
    );
    await host(t, f);
    await t.tap(find.byKey(const Key('chatMenu')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('menuMute')));
    await settleUi(t);
    expect(
      find.text('Could not save the mute preference. Try again.'),
      findsOneWidget,
    );
  });
  testWidgets('copy failure shows safe feedback', (t) async {
    final f = UiFixture();
    await f.seed();
    await host(t, f);
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          throw PlatformException(code: 'clipboard');
        }
        return null;
      },
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final bubble = t
        .widgetList<MessageBubble>(find.byType(MessageBubble))
        .first;
    bubble.actions.firstWhere((a) => a.id == 'copy').onSelected();
    await settleUi(t);
    expect(
      find.text('Could not copy this message. Try again.'),
      findsOneWidget,
    );
  });
  testWidgets(
    'own send opens latest from a search result with reduced motion',
    (t) async {
      final f = UiFixture();
      await f.seed();
      await host(t, f, initialMessageId: '1', reducedMotion: true);
      expect(find.byKey(const Key('searchLocation')), findsOneWidget);
      await send(t);
      expect(find.byKey(const Key('searchLocation')), findsNothing);
      expect(
        t
            .widget<ListView>(find.byKey(const Key('messageTimeline')))
            .controller!
            .offset,
        0,
      );
    },
  );
  testWidgets('queued visibility callback safely clears after disposal', (
    t,
  ) async {
    final f = UiFixture();
    await host(t, f);
    final dynamic state = t.state(find.byType(ChatScreen));
    state.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await t.pumpWidget(const SizedBox());
    await t.pump();
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'documents current behaviour: disposing during confirmed local save swallows late cleanup',
    (t) async {
      final c = ActionChat()..actionHold = Completer<void>();
      await pending(t, c, SendOutcome.publishUnknown);
      final container = ProviderScope.containerOf(
        t.element(find.byType(ChatScreen)),
      );
      await t.tap(find.byKey(const Key('checkSendStatus')));
      await t.pump();
      expect(c.saves, 1);
      // Keep the provider scope alive while disposing just the screen.
      final scope = t.widget<ProviderScope>(find.byType(ProviderScope));
      await t.pumpWidget(
        ProviderScope(
          overrides: scope.overrides,
          child: const MaterialApp(home: SizedBox()),
        ),
      );
      c.actionHold!.complete();
      await settleUi(t);
      expect(t.takeException(), isNull);
      expect(container.read(pendingLocalSendsProvider).values, hasLength(1));
    },
  );
}
