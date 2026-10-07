import 'dart:async';

import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/chat/message_limits.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/model/chat/pending_sends.dart';
import 'package:fireplace/src/view/safety/requests_screen.dart';
import 'package:fireplace/src/model/notifications/chat_activity.dart';
import 'package:fireplace/src/view/chat_list/chat_list_screen.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:fireplace/src/view/chat/forward/forward_message.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';
import 'chat_features_test.dart' show mount, container;

void main() {
  testWidgets(
    'leaving a pending forward stops later recipients and retains late uncertainty',
    (t) async {
      final f = UiFixture();
      await f.seed();
      f.chat.summaries.add(ChatSummary('alice_jeff', 'jeff', fixtureTime));
      addTearDown(f.session.close);
      await mount(
        t,
        f,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ForwardMessageScreen(
                    message: message(
                      id: 'source-late',
                      body: 'late body',
                      outgoing: true,
                    ),
                  ),
                ),
              ),
              child: const Text('Open forward'),
            ),
          ),
        ),
      );
      final c = container(t);
      await t.tap(find.text('Open forward'));
      await settleUi(t);
      await t.tap(find.byKey(const ValueKey('forwardRecipient-alice_bob')));
      await t.tap(find.byKey(const ValueKey('forwardRecipient-alice_jeff')));
      await t.pump();
      f.chat.sendHold = Completer<void>();
      f.chat.sendError = SendNotConfirmedException(
        outcome: SendOutcome.publishUnknown,
        chatId: 'alice_bob',
        messageId: 'late-warning',
        body: 'late body',
        attemptedAt: fixtureTime,
        persisted: false,
      );
      await t.ensureVisible(find.byKey(const Key('forwardSend')));
      await t.tap(find.byKey(const Key('forwardSend')));
      await t.pump();
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.byType(ForwardMessageScreen), findsNothing);
      f.chat.sendHold!.complete();
      await settleUi(t);
      expect(f.chat.sends, ['late body']);
      expect(
        c.read(pendingLocalSendsProvider).values.single.messageId,
        'late-warning',
      );
      await t.pumpWidget(const SizedBox());
    },
  );
  for (final identity in [false, true]) {
    testWidgets(
      'definite forward failure has safe not-sent wording (identity=$identity)',
      (t) async {
        final f = UiFixture();
        await f.seed();
        addTearDown(f.session.close);
        f.chat.sendError = identity
            ? IdentityChangedException('bob', [1])
            : ChatException('unsafe internal details');
        await mount(
          t,
          f,
          ForwardMessageScreen(
            message: message(id: 'source', body: 'body', outgoing: true),
          ),
        );
        await t.tap(find.byKey(const ValueKey('forwardRecipient-alice_bob')));
        await t.pump();
        await t.ensureVisible(find.byKey(const Key('forwardSend')));
        await t.tap(find.byKey(const Key('forwardSend')));
        await settleUi(t);
        expect(find.textContaining('Not sent —'), findsOneWidget);
        expect(find.textContaining('Could not confirm'), findsNothing);
        expect(find.textContaining('unsafe internal details'), findsNothing);
        expect(f.chat.sends, ['body']);
      },
    );
  }
  testWidgets(
    'requests remain hidden while safety preferences are loading or fail',
    (t) async {
      final f = UiFixture();
      await f.seed();
      addTearDown(f.session.close);
      final hidden = Completer<Set<String>>();
      f.hiddenFuture = hidden.future;
      await mount(t, f, const RequestsScreen());
      expect(find.byKey(const Key('request_alice_theo')), findsNothing);
      hidden.completeError(StateError('unavailable'));
      await settleUi(t);
      expect(find.byKey(const Key('request_alice_theo')), findsNothing);
      expect(find.text('Could not load requests'), findsOneWidget);
    },
  );
  testWidgets(
    'composer caps emoji by code point and rejects programmatic bypass',
    (t) async {
      final f = UiFixture();
      await f.seed();
      addTearDown(f.session.close);
      await mount(t, f, const ChatScreen(chatId: 'alice_fred'));
      final composer = find.byKey(const Key('composer'));
      await t.enterText(composer, '🙂' * (maxMessageCharacters + 1));
      await t.pump();
      final controller = t.widget<TextField>(composer).controller!;
      expect(controller.text, '🙂' * maxMessageCharacters);
      expect(find.text('16384 / 16,384'), findsOneWidget);
      controller.text = 'x' * (maxMessageCharacters + 1);
      await t.pump();
      await t.tap(find.byKey(const Key('send')));
      await settleUi(t);
      expect(f.chat.sends, isEmpty);
      expect(find.text(messageLimitError), findsOneWidget);
      await t.enterText(composer, '🙂' * maxMessageCharacters);
      await t.tap(find.byKey(const Key('send')));
      await settleUi(t);
      expect(f.chat.sends.single, '🙂' * maxMessageCharacters);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'oversized receive is clipped literal, expandable, copied raw and cannot forward',
    (t) async {
      final f = UiFixture();
      await f.seed();
      addTearDown(f.session.close);
      final raw = '**literal** \\_text_ ${'x' * maxMessageCharacters}';
      await f.chat.store.add(
        message(
          id: 'oversized',
          body: raw,
          at: fixtureTime.add(const Duration(minutes: 1)),
        ),
      );
      String? copied;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
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
      await mount(t, f, const ChatScreen(chatId: 'alice_fred'));
      final bubble = find.byKey(const ValueKey('messageBubble-oversized'));
      Text text() => t.widget<Text>(
        find.descendant(
          of: bubble,
          matching: find.byWidgetPredicate(
            (w) => w is Text && w.textSpan != null,
          ),
        ),
      );
      expect(
        text().textSpan!.toPlainText(),
        '${clipMessage(raw, oversizedPreviewCharacters)}…',
      );
      await t.tap(find.byKey(const ValueKey('showAll-oversized')));
      await t.pump();
      expect(text().textSpan!.toPlainText(), raw);
      // Collapse before opening its footer menu, which is offscreen when expanded.
      await t.ensureVisible(find.byKey(const ValueKey('showAll-oversized')));
      await t.tap(find.byKey(const ValueKey('showAll-oversized')));
      await t.pump();
      await t.longPress(bubble);
      await t.pumpAndSettle();
      expect(find.text('Forward'), findsNothing);
      await t.tap(find.text('Copy'));
      await t.pumpAndSettle();
      expect(copied, raw);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('oversized forwarding cannot call send', (t) async {
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    await mount(
      t,
      f,
      ForwardMessageScreen(
        message: message(
          id: 'oversize-forward',
          body: '🙂' * (maxMessageCharacters + 1),
          outgoing: true,
        ),
      ),
    );
    await t.tap(find.byKey(const ValueKey('forwardRecipient-alice_bob')));
    await t.pump();
    await t.ensureVisible(find.byKey(const Key('forwardSend')));
    await t.tap(find.byKey(const Key('forwardSend')));
    await settleUi(t);
    expect(f.chat.sends, isEmpty);
    expect(find.textContaining('cannot be forwarded'), findsOneWidget);
  });

  testWidgets(
    'switching previews off hides both name and body in notifications',
    (t) async {
      final f = UiFixture();
      await f.seed();
      addTearDown(f.session.close);
      await mount(t, f, const ChatListScreen(), notices: true);
      await t.tap(find.byKey(const Key('settings')));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.byKey(const Key('notificationPreviews')),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await t.tap(find.byKey(const Key('notificationPreviews')));
      await settleUi(t);
      expect(container(t).read(chatActivityProvider).previewText, isFalse);
      await t.pageBack();
      await t.pumpAndSettle();
      await f.chat.store.add(
        message(
          id: 'private-notice',
          body: 'hidden body',
          at: fixtureTime.add(const Duration(minutes: 1)),
        ),
      );
      await settleUi(t);
      final notice = find.byKey(const Key('inAppNotification'));
      expect(notice, findsOneWidget);
      expect(
        find.descendant(of: notice, matching: find.text('New message')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: notice, matching: find.text('Fred')),
        findsNothing,
      );
      expect(
        find.descendant(of: notice, matching: find.text('hidden body')),
        findsNothing,
      );
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'block hides list, counts and notices; unblock restores untouched history',
    (t) async {
      final f = UiFixture();
      await f.seed();
      addTearDown(f.session.close);
      await mount(t, f, const ChatListScreen(), notices: true);
      final c = container(t);
      final history = await t.runAsync(
        () => f.chat.store.watch('alice_fred').first,
      );
      f.blocked = {'fred'};
      c.invalidate(blockedUidsProvider);
      await settleUi(t);
      expect(
        find.byKey(const ValueKey('conversation-alice_fred')),
        findsNothing,
      );
      expect(
        c.read(chatActivityProvider).unread.containsKey('alice_fred'),
        isFalse,
      );
      await f.chat.store.add(
        message(id: 'blocked-arrival', body: 'blocked secret'),
      );
      await settleUi(t);
      expect(find.byKey(const Key('inAppNotification')), findsNothing);
      f.blocked = {};
      c.invalidate(blockedUidsProvider);
      await settleUi(t);
      expect(
        find.byKey(const ValueKey('conversation-alice_fred')),
        findsOneWidget,
      );
      final restored = (await t.runAsync(
        () => f.chat.store.watch('alice_fred').first,
      ))!;
      expect(restored.map((m) => m.id), containsAll(history!.map((m) => m.id)));
      expect(restored.any((m) => m.id == 'blocked-arrival'), isTrue);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets('direct blocked conversation does not display message history', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    f.blocked = {'fred'};
    addTearDown(f.session.close);
    await mount(t, f, const ChatScreen(chatId: 'alice_fred'));
    expect(find.text('Conversation hidden'), findsOneWidget);
    expect(find.byKey(const ValueKey('messageBubble-1')), findsNothing);
    expect(await f.chat.store.get('alice_fred', '1'), isNotNull);
  });
}
