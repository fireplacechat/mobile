import 'dart:async';

import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/settings/local_chat_preferences.dart';
import 'package:fireplace/src/ui/settings_screen.dart';
import 'package:fireplace/src/model/chat/chat_visibility.dart';
import 'package:fireplace/src/model/notifications/chat_activity.dart';
import 'package:fireplace/src/view/chat/chat_route_observer.dart';
import 'package:fireplace/src/ui/chat_list_screen.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:fireplace/src/view/chat/forward/forward_message.dart';
import 'package:fireplace/src/view/notifications/in_app_notice.dart';
import 'package:fireplace/src/view/search/message_search_results.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/model/chat/chat_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';
import 'chat_features_test.dart' show RecordingChat;

class _BrokenPreferences extends LocalChatPreferences {
  bool broken = true;
  @override
  bool get available => !broken;
  @override
  Future<void> reset({Map<String, Set<String>> history = const {}}) {
    broken = false;
    return super.reset(history: history);
  }
}

Future<void> mount(
  WidgetTester t,
  UiFixture f,
  Widget page, {
  bool notice = false,
  double scale = 1,
}) async {
  final key = GlobalKey<NavigatorState>();
  await t.pumpWidget(
    ProviderScope(
      overrides: f.overrides,
      child: MaterialApp(
        navigatorKey: key,
        navigatorObservers: [chatRouteObserver],
        theme: fireplaceTheme(Brightness.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: notice
              ? InAppNoticeHost(navigatorKey: key, child: child!)
              : child!,
        ),
        home: page,
      ),
    ),
  );
  await settleUi(t);
}

ProviderContainer scope(WidgetTester t) =>
    ProviderScope.containerOf(t.element(find.byType(Scaffold).first));
void main() {
  testWidgets(
    'broken local preferences suppress notifications, settings reset preserves chat history',
    (t) async {
      final prefs = _BrokenPreferences();
      final f = UiFixture(chatPreferences: prefs);
      await f.seed();
      addTearDown(f.session.close);
      await mount(t, f, const ChatListScreen(), notice: true);
      expect(scope(t).read(chatActivityProvider).unread, isEmpty);
      await f.chat.store.add(message(id: 'silent', body: 'private'));
      await settleUi(t);
      expect(find.byKey(const Key('inAppNotification')), findsNothing);
      await t.tap(find.byKey(const Key('settings')));
      await t.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      await t.tap(find.byKey(const Key('resetChatPreferences')));
      await t.pumpAndSettle();
      await t.tap(find.text('Reset'));
      await settleUi(t);
      await t.pumpAndSettle();
      expect(prefs.available, isTrue);
      expect(await f.chat.store.get('alice_fred', 'silent'), isNotNull);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'popping a chat must not suppress subsequent foreground arrivals',
    (t) async {
      final f = UiFixture();
      await f.seed();
      addTearDown(f.session.close);
      await mount(t, f, const ChatListScreen(), notice: true);
      await t.tap(find.byKey(const ValueKey('conversation-alice_fred')));
      await t.pumpAndSettle();
      expect(scope(t).read(visibleChatProvider), 'alice_fred');
      await t.tap(find.byKey(const Key('chatBack')));
      await t.pumpAndSettle();
      expect(scope(t).read(visibleChatProvider), isNull);
      await f.chat.store.add(message(id: 'after-pop', body: 'new'));
      await settleUi(t);
      await t.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const Key('inAppNotification')), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'a security hold revokes a visible preview before it can be tapped',
    (t) async {
      final f = UiFixture();
      await f.seed();
      addTearDown(f.session.close);
      await f.session.chatPreferences.previews(true);
      await mount(t, f, const ChatListScreen(), notice: true);
      await f.chat.store.add(message(id: 'alert', body: 'private-preview'));
      await settleUi(t);
      await t.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const Key('inAppNotification')), findsOneWidget);
      f.alerts = {
        'fred': [1],
      };
      scope(t).invalidate(identityAlertsProvider);
      await settleUi(t);
      expect(find.byKey(const Key('inAppNotification')), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'recipient blocked during a forward batch is not sent the next copy',
    (t) async {
      final chat = RecordingChat();
      final f = UiFixture(chat: chat);
      await f.seed();
      addTearDown(f.session.close);
      f.chat.summaries.add(ChatSummary('alice_jeff', 'jeff', fixtureTime));
      await mount(
        t,
        f,
        ForwardMessageScreen(
          message: message(id: 'source', body: 'body', outgoing: true),
        ),
      );
      await t.tap(find.byKey(const ValueKey('forwardRecipient-alice_bob')));
      await t.tap(find.byKey(const ValueKey('forwardRecipient-alice_jeff')));
      await t.pump();
      chat.sendHold = Completer<void>();
      await t.tap(find.byKey(const Key('forwardSend')));
      await t.pump();
      f.blocked = {'jeff'};
      scope(t).invalidate(blockedUidsProvider);
      await settleUi(t);
      chat.sendHold!.complete();
      await settleUi(t);
      expect(chat.targets, ['alice_bob']);
      expect(
        find.byKey(const ValueKey('forwardRecipient-alice_jeff')),
        findsNothing,
      );
    },
  );
  testWidgets(
    'source put on hold mid-batch stops forwarding to more recipients',
    (t) async {
      final chat = RecordingChat();
      final f = UiFixture(chat: chat);
      await f.seed();
      addTearDown(f.session.close);
      f.chat.summaries.add(ChatSummary('alice_jeff', 'jeff', fixtureTime));
      await mount(
        t,
        f,
        ForwardMessageScreen(
          message: message(id: 'source', body: 'body', outgoing: true),
        ),
      );
      await t.tap(find.byKey(const ValueKey('forwardRecipient-alice_bob')));
      await t.tap(find.byKey(const ValueKey('forwardRecipient-alice_jeff')));
      await t.pump();
      chat.sendHold = Completer<void>();
      await t.tap(find.byKey(const Key('forwardSend')));
      await t.pump();
      f.alerts = {
        'fred': [1],
      };
      scope(t).invalidate(identityAlertsProvider);
      await settleUi(t);
      chat.sendHold!.complete();
      await settleUi(t);
      expect(chat.targets, ['alice_bob']);
      expect(find.textContaining('Nothing more was forwarded'), findsOneWidget);
    },
  );
  testWidgets(
    'global message result navigates to exact message and shows local date',
    (t) async {
      final f = UiFixture();
      await f.seed();
      addTearDown(f.session.close);
      await mount(t, f, const ChatListScreen());
      await t.enterText(find.byKey(const Key('chatSearch')), 'Saturday');
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      // Await the actual isolate search while outside the test's virtual clock.
      final c = scope(t);
      for (
        var attempt = 0;
        attempt < 30 && !c.read(messageSearchProvider('saturday')).hasValue;
        attempt++
      ) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await t.pump(const Duration(milliseconds: 30));
      }
      expect(c.read(messageSearchProvider('saturday')).hasValue, isTrue);
      await t.pump();
      await settleUi(t);
      final hit = find.byKey(const ValueKey('searchHit-alice_fred-1'));
      await t.scrollUntilVisible(
        hit,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(hit);
      await t.pumpAndSettle();
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(
        t.widget<ChatScreen>(find.byType(ChatScreen)).initialMessageId,
        '1',
      );
      expect(find.text('Are we still on for Saturday?'), findsOneWidget);
      expect(find.text('Around two? There is no rush.'), findsNothing);
    },
  );
  testWidgets(
    'notification card remains usable at 3x text on a narrow screen',
    (t) async {
      final f = UiFixture();
      await f.seed();
      addTearDown(f.session.close);
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await mount(t, f, const ChatListScreen(), notice: true, scale: 3);
      await f.chat.store.add(message(id: 'large-alert', body: 'message'));
      await settleUi(t);
      await t.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const Key('inAppNotification')), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
}
