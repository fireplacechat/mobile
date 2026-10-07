import 'dart:async';

import 'package:fireplace/src/ui/chat_activity.dart';
import 'package:fireplace/src/ui/chat_list_screen.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:fireplace/src/view/chat/forward/forward_message.dart';
import 'package:fireplace/src/view/notifications/in_app_notice.dart';
import 'package:fireplace/src/ui/recovery_screens.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/model/chat/chat_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

class RecordingChat extends FixtureChat {
  final targets = <String>[];
  @override
  Future<void> sendText(String chatId, String body) async {
    targets.add(chatId);
    await super.sendText(chatId, body);
  }
}

Future<void> mount(
  WidgetTester t,
  UiFixture f,
  Widget home, {
  bool notices = false,
}) async {
  final key = GlobalKey<NavigatorState>();
  await t.pumpWidget(
    ProviderScope(
      overrides: f.overrides,
      child: MaterialApp(
        navigatorKey: key,
        navigatorObservers: [chatRouteObserver],
        theme: fireplaceTheme(Brightness.light),
        builder: notices
            ? (context, child) =>
                  InAppNoticeHost(navigatorKey: key, child: child!)
            : null,
        home: home,
      ),
    ),
  );
  await settleUi(t);
}

ProviderContainer container(WidgetTester t) =>
    ProviderScope.containerOf(t.element(find.byType(Scaffold).first));
void main() {
  testWidgets(
    'formatting is accessible, selectable in a sheet, and copy strips markers',
    (t) async {
      final f = UiFixture();
      await f.seed();
      addTearDown(f.session.close);
      await f.chat.store.add(
        message(
          id: 'formatted',
          body: '**Hello** _Fred_ ~~later~~',
          at: fixtureTime.add(const Duration(minutes: 1)),
        ),
      );
      final semantics = t.ensureSemantics();

      await mount(t, f, const ChatScreen(chatId: 'alice_fred'));
      final selectable = t.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('messageBubble-formatted')),
          matching: find.byWidgetPredicate(
            (w) => w is Text && w.textSpan != null,
          ),
        ),
      );
      expect(selectable.textSpan!.toPlainText(), 'Hello Fred later');
      expect(selectable.semanticsLabel, 'Hello Fred later');
      expect(
        t
            .getSemantics(find.byKey(const ValueKey('messageBubble-formatted')))
            .toStringDeep(),
        isNot(contains('**Hello**')),
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
      await t.longPress(find.byKey(const ValueKey('messageBubble-formatted')));
      await t.pumpAndSettle();
      await t.tap(find.text('Copy'));
      await t.pumpAndSettle();
      expect(copied, 'Hello Fred later');
      semantics.dispose();
    },
  );
  testWidgets(
    'opening one conversation clears only its count; back badge shows others',
    (t) async {
      final f = UiFixture();
      await f.seed();
      addTearDown(f.session.close);
      await mount(t, f, const ChatListScreen());
      expect(find.byKey(const ValueKey('unread-alice_fred')), findsOneWidget);
      final c = container(t);
      await t.tap(find.byKey(const ValueKey('conversation-alice_bob')));
      await t.pumpAndSettle();
      await settleUi(t);
      expect(c.read(chatActivityProvider).unread['alice_fred'], 3);
      expect(
        t.widget<IconButton>(find.byKey(const Key('chatBack'))).tooltip,
        contains('3 unread'),
      );
      await t.tap(find.byKey(const Key('chatBack')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('conversation-alice_fred')));
      await t.pumpAndSettle();
      await settleUi(t);
      expect(c.read(chatActivityProvider).unread['alice_fred'], 0);
    },
  );
  testWidgets('list and chat menu mute and unmute the same local preference', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    await mount(t, f, const ChatListScreen());
    final c = container(t);
    await t.tap(find.byKey(const ValueKey('conversationMenu-alice_fred')));
    await t.pumpAndSettle();
    await t.tap(find.text('Mute chat'));
    await t.pumpAndSettle();
    expect(c.read(chatActivityProvider).muted, contains('alice_fred'));
    await t.tap(find.byKey(const ValueKey('conversation-alice_fred')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('chatMenu')));
    await t.pumpAndSettle();
    await t.tap(find.text('Unmute chat'));
    await t.pumpAndSettle();
    expect(c.read(chatActivityProvider).muted, isEmpty);
  });
  testWidgets(
    'foreground notification shows text by default, tap opens and marks seen',
    (t) async {
      final f = UiFixture();
      await f.seed();
      addTearDown(f.session.close);
      await mount(t, f, const ChatListScreen(), notices: true);
      expect(find.byKey(const Key('inAppNotification')), findsNothing);
      await f.chat.store.add(
        message(
          id: 'arrives',
          body: 'secret preview',
          at: fixtureTime.add(const Duration(minutes: 1)),
        ),
      );
      await settleUi(t);
      await t.pump(const Duration(milliseconds: 200));
      final notice = find.byKey(const Key('inAppNotification'));
      expect(notice, findsOneWidget);
      expect(
        find.descendant(of: notice, matching: find.text('secret preview')),
        findsOneWidget,
      );
      await t.tap(notice);
      await t.pumpAndSettle();
      await settleUi(t);
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(notice, findsNothing);
      expect(container(t).read(chatActivityProvider).unread['alice_fred'], 0);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'muted, current-chat and background arrivals never raise a card',
    (t) async {
      final f = UiFixture();
      await f.seed();
      addTearDown(f.session.close);
      await mount(t, f, const ChatListScreen(), notices: true);
      final c = container(t);
      await c.read(chatActivityProvider.notifier).mute('alice_fred', true);
      await settleUi(t);
      await f.chat.store.add(message(id: 'muted', body: 'quiet'));
      await settleUi(t);
      expect(find.byKey(const Key('inAppNotification')), findsNothing);
      await c.read(chatActivityProvider.notifier).mute('alice_fred', false);
      await settleUi(t);
      await t.tap(find.byKey(const ValueKey('conversation-alice_fred')));
      await t.pumpAndSettle();
      await f.chat.store.add(message(id: 'current', body: 'here'));
      await settleUi(t);
      expect(find.byKey(const Key('inAppNotification')), findsNothing);
      await t.tap(find.byKey(const Key('chatBack')));
      await t.pumpAndSettle();
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await f.chat.store.add(message(id: 'background', body: 'later'));
      await settleUi(t);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settleUi(t);
      expect(find.byKey(const Key('inAppNotification')), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('opted-in preview auto-dismisses and swipe dismissal works', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    await f.session.chatPreferences.previews(true);
    await mount(t, f, const ChatListScreen(), notices: true);
    await f.chat.store.add(message(id: 'new', body: '**Preview**'));
    await settleUi(t);
    await t.pump(const Duration(milliseconds: 200));
    expect(
      find.descendant(
        of: find.byKey(const Key('inAppNotification')),
        matching: find.text('Preview'),
      ),
      findsOneWidget,
    );
    await t.pump(const Duration(seconds: 6));
    expect(find.byKey(const Key('inAppNotification')), findsNothing);
    await f.chat.store.add(message(id: 'second', body: 'Again'));
    await settleUi(t);
    await t.pump(const Duration(milliseconds: 200));
    await t.drag(
      find.byKey(const Key('inAppNotification')),
      const Offset(700, 0),
    );
    await t.pumpAndSettle();
    expect(find.byKey(const Key('inAppNotification')), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'forward multiple recipients once, exclude requests/blocks/holds/caps',
    (t) async {
      final chat = RecordingChat();
      final f = UiFixture(chat: chat);
      await f.seed();
      addTearDown(f.session.close);
      f.chat.summaries.addAll([
        ChatSummary('alice_jeff', 'jeff', fixtureTime),
        ChatSummary(
          'alice_steve',
          'steve',
          fixtureTime,
          accepted: false,
          initiator: 'alice',
          requestCount: 3,
        ),
        ChatSummary('alice_katy', 'katy', fixtureTime),
      ]);
      f.blocked = {'katy'};
      await mount(
        t,
        f,
        ForwardMessageScreen(
          message: message(id: '1', body: '**Keep** this', outgoing: true),
        ),
      );
      expect(
        find.byKey(const ValueKey('forwardRecipient-alice_theo')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('forwardRecipient-alice_steve')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('forwardRecipient-alice_katy')),
        findsNothing,
      );
      await t.tap(find.byKey(const ValueKey('forwardRecipient-alice_bob')));
      await t.tap(find.byKey(const ValueKey('forwardRecipient-alice_jeff')));
      await t.pump();
      chat.sendHold = Completer<void>();
      final send = t
          .widget<FilledButton>(find.byKey(const Key('forwardSend')))
          .onPressed!;
      send();
      send();
      await t.pump();
      expect(chat.targets, ['alice_bob']);
      chat.sendHold!.complete();
      await settleUi(t);
      expect(chat.targets, ['alice_bob', 'alice_jeff']);
      expect(chat.sends, ['**Keep** this', '**Keep** this']);
      expect(
        t.widget<FilledButton>(find.byKey(const Key('forwardSend'))).onPressed,
        isNull,
      );
    },
  );
  testWidgets('uncertain forward cannot be retried by repeated send taps', (
    t,
  ) async {
    final chat = RecordingChat();
    final f = UiFixture(chat: chat);
    await f.seed();
    addTearDown(f.session.close);
    chat.sendError = SendNotConfirmedException(
      chatId: 'alice_bob',
      messageId: 'uncertain',
      body: 'text',
      attemptedAt: fixtureTime,
      outcome: SendOutcome.publishUnknown,
      persisted: true,
    );
    await mount(
      t,
      f,
      ForwardMessageScreen(
        message: message(id: '1', body: 'text', outgoing: true),
      ),
    );
    await t.tap(find.byKey(const ValueKey('forwardRecipient-alice_bob')));
    await t.pump();
    await t.ensureVisible(find.byKey(const Key('forwardSend')));
    await t.tap(find.byKey(const Key('forwardSend')));
    await settleUi(t);
    expect(chat.targets, ['alice_bob']);
    expect(find.textContaining('Not confirmed'), findsOneWidget);
    expect(
      t.widget<FilledButton>(find.byKey(const Key('forwardSend'))).onPressed,
      isNull,
    );
  });
  testWidgets('incoming forward asks before opening recipient selector', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    await mount(t, f, const ChatScreen(chatId: 'alice_fred'));
    await t.longPress(find.byKey(const ValueKey('messageBubble-5')));
    await t.pumpAndSettle();
    await t.tap(find.text('Forward'));
    await t.pumpAndSettle();
    expect(find.textContaining('You are sharing text @fred'), findsOneWidget);
    expect(find.byType(ForwardMessageScreen), findsNothing);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(f.chat.sends, isEmpty);
  });
  testWidgets(
    'search location opens old message without marking newer messages seen',
    (t) async {
      final f = UiFixture();
      await f.seed();
      addTearDown(f.session.close);
      await mount(
        t,
        f,
        const ChatScreen(chatId: 'alice_fred', initialMessageId: '1'),
      );
      expect(find.text('Are we still on for Saturday?'), findsOneWidget);
      expect(find.text('Around two? There is no rush.'), findsNothing);
      expect(container(t).read(chatActivityProvider).unread['alice_fred'], 2);
      await t.tap(find.text('Show latest messages'));
      await settleUi(t);
      expect(find.text('Around two? There is no rush.'), findsOneWidget);
      expect(container(t).read(chatActivityProvider).unread['alice_fred'], 0);
    },
  );
  testWidgets(
    'link page title and main instructions are centered, large and scrollable',
    (t) async {
      final f = UiFixture();
      addTearDown(f.session.close);
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await mount(t, f, const LinkNewDeviceScreen());
      final title = t.widget<Text>(find.text('Link a new device'));
      expect(title.textAlign, TextAlign.center);
      expect(title.style!.fontSize, 28);
      expect(find.text('Sign in on the new device'), findsOneWidget);
      await t.scrollUntilVisible(
        find.byKey(const Key('scanLink')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pump();
      expect(t.takeException(), isNull);
    },
  );
}
