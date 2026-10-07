import 'package:fireplace/src/app/providers.dart';

import 'dart:async';

import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/model/chat/pending_sends.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/ui/chat_activity.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:fireplace/src/view/chat/chat_details_screen.dart';
import 'package:fireplace/src/view/safety/verify_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';
import 'chat_screen_pinning_test.dart' show host, send;

class RecordingSafety extends FixtureSafety {
  final blocks = <String>[];
  final unblocks = <String>[];
  final reports = <(String, String?)>[];
  Completer<void>? hold;
  @override
  Future<void> block(String peerUid) async {
    blocks.add(peerUid);
    await hold?.future;
  }

  @override
  Future<void> unblock(String peerUid) async {
    unblocks.add(peerUid);
    await hold?.future;
  }

  @override
  Future<void> report({
    required String peerUid,
    required ReportReason reason,
    String? chatId,
    String? note,
    List<String> context = const [],
  }) async => reports.add((peerUid, chatId));
}

Future<void> customHost(
  WidgetTester t,
  UiFixture f,
  List<Override> extra,
) async {
  addTearDown(f.session.close);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        for (final original in f.overrides)
          if (!extra.any((e) => e.origin == original.origin)) original,
        ...extra,
      ],
      child: MaterialApp(
        theme: fireplaceTheme(Brightness.light),
        navigatorObservers: [chatRouteObserver],
        home: const ChatScreen(chatId: 'alice_fred'),
      ),
    ),
  );
  await settleUi(t);
}

void main() {
  testWidgets(
    'same last id does not scroll; a new arrival near the bottom does',
    (t) async {
      final f = UiFixture();
      for (var i = 0; i < 40; i++) {
        await f.chat.store.add(
          message(
            id: '$i',
            body: 'Message $i',
            at: fixtureTime.add(Duration(minutes: i)),
          ),
        );
      }
      await host(t, f);
      final scroll = t
          .widget<ListView>(find.byKey(const Key('messageTimeline')))
          .controller!;
      scroll.jumpTo(40);
      await t.pump();
      await f.chat.store.add(
        message(
          id: '39',
          body: 'Updated text',
          at: fixtureTime.add(const Duration(minutes: 39)),
        ),
      );
      await settleUi(t);
      expect(scroll.offset, 40);
      await f.chat.store.add(
        message(
          id: 'new',
          body: 'New arrival',
          at: fixtureTime.add(const Duration(hours: 2)),
        ),
      );
      await settleUi(t);
      expect(scroll.offset, 0);
    },
  );
  testWidgets('hidden route does not clear another chat visible marker', (
    t,
  ) async {
    final f = UiFixture();
    await host(t, f);
    final c = ProviderScope.containerOf(t.element(find.byType(ChatScreen)));
    Navigator.of(t.element(find.byType(ChatScreen))).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Other screen')),
      ),
    );
    c.read(visibleChatProvider.notifier).show('alice_bob');
    await t.pumpAndSettle();
    expect(c.read(visibleChatProvider), 'alice_bob');
    Navigator.of(t.element(find.text('Other screen'))).pop();
    await t.pumpAndSettle();
    expect(c.read(visibleChatProvider), 'alice_fred');
  });

  testWidgets(
    'initial resumed lifecycle, pause, and resume update visibility',
    (t) async {
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      addTearDown(
        () =>
            t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed),
      );
      final f = UiFixture();
      await host(t, f);
      final c = ProviderScope.containerOf(t.element(find.byType(ChatScreen)));
      expect(c.read(visibleChatProvider), 'alice_fred');
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      t.binding.scheduleWarmUpFrame();
      await t.pump();
      expect(c.read(visibleChatProvider), isNull);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump();
      expect(c.read(visibleChatProvider), 'alice_fred');
    },
  );

  testWidgets(
    'Return to chats pops the unavailable conversation to first route',
    (t) async {
      final f = UiFixture();
      addTearDown(f.session.close);
      final session = ValueNotifier<AsyncValue<AppSession?>>(
        AsyncData(f.session),
      );
      addTearDown(session.dispose);
      await t.pumpWidget(
        ProviderScope(
          overrides: f.overrides,
          child: ValueListenableBuilder(
            valueListenable: session,
            builder: (_, value, _) => ProviderScope(
              overrides: [appSessionProvider.overrideWithValue(value)],
              child: MaterialApp(
                theme: fireplaceTheme(Brightness.light),
                navigatorObservers: [chatRouteObserver],
                home: Builder(
                  builder: (context) => Scaffold(
                    body: TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              const ChatScreen(chatId: 'alice_fred'),
                        ),
                      ),
                      child: const Text('Open chat'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Open chat'));
      await settleUi(t);
      await t.pumpAndSettle();
      session.value = const AsyncData(null);
      await settleUi(t);
      expect(find.text('Return to chats'), findsOneWidget);
      await t.tap(find.text('Return to chats'));
      await t.pumpAndSettle();
      expect(find.byType(ChatScreen), findsNothing);
      expect(find.text('Open chat'), findsOneWidget);
    },
  );

  testWidgets('privacy settings error retry invalidates the failing provider', (
    t,
  ) async {
    var calls = 0;
    final f = UiFixture();
    await customHost(t, f, [
      blockedUidsProvider.overrideWith((ref) {
        calls++;
        return calls == 1
            ? Stream.error(StateError('privacy'))
            : Stream.value(<String>{});
      }),
    ]);
    expect(find.text('Could not load privacy settings'), findsOneWidget);
    await t.tap(find.text('Try again'));
    await settleUi(t);
    expect(calls, 2);
    expect(find.text('Could not load privacy settings'), findsNothing);
  });

  testWidgets(
    'stored confirmation silently drops memory and cleans pending next frame',
    (t) async {
      final f = UiFixture()
        ..chat.sendError = SendNotConfirmedException(
          outcome: SendOutcome.publishUnknown,
          chatId: 'alice_fred',
          messageId: 'pending',
          body: 'hello',
          attemptedAt: fixtureTime,
          persisted: false,
        );
      await host(t, f);
      await send(t);
      final c = ProviderScope.containerOf(t.element(find.byType(ChatScreen)));
      expect(c.read(pendingLocalSendsProvider), hasLength(1));
      await f.chat.store.add(
        message(id: 'pending', body: 'hello', outgoing: true),
      );
      await settleUi(t);
      expect(c.read(pendingLocalSendsProvider), isEmpty);
      expect(find.text('Message not confirmed'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );

  for (final blocked in [false, true]) {
    testWidgets(
      'contact name opens details with working ${blocked ? "unblock" : "block"} callback',
      (t) async {
        final safety = RecordingSafety();
        final f = UiFixture(safety: safety)..blocked = blocked ? {'fred'} : {};
        await host(t, f);
        final c = ProviderScope.containerOf(t.element(find.byType(ChatScreen)));
        await t.tap(find.byKey(const Key('chatDetails')));
        await t.pumpAndSettle();
        expect(find.byType(ChatDetailsScreen), findsOneWidget);
        expect(c.read(visibleChatProvider), isNull);
        await t.tap(find.byKey(const Key('detailsBlock')));
        await settleUi(t);
        await t.pump(const Duration(milliseconds: 300));
        if (blocked) {
          expect(safety.unblocks, ['fred']);
          Navigator.of(t.element(find.byType(ChatDetailsScreen))).pop();
          await t.pumpAndSettle();
          expect(c.read(visibleChatProvider), 'alice_fred');
        } else {
          await t.tap(find.byKey(const Key('confirmBlock')));
          await t.pumpAndSettle();
          expect(safety.blocks, ['fred']);
          expect(find.byType(ChatDetailsScreen), findsNothing);
        }
      },
    );
  }
  testWidgets(
    'verified shield is highlighted and opens the security code screen',
    (t) async {
      final f = UiFixture()..verified = true;
      await host(t, f);
      final button = t.widget<IconButton>(find.byKey(const Key('verify')));
      final icon = button.icon as Icon;
      expect(icon.icon, Icons.verified_user);
      expect(
        icon.color,
        Theme.of(t.element(find.byKey(const Key('verify'))))
            .colorScheme
            .primary,
      );
      await t.tap(find.byKey(const Key('verify')));
      await settleUi(t);
      await t.pumpAndSettle();
      expect(find.byType(VerifyScreen), findsOneWidget);
      expect(find.text('Verified'), findsOneWidget);
    },
  );
  for (final source in ['menu', 'composer']) {
    testWidgets('$source unblock uses the contact guard', (t) async {
      final safety = RecordingSafety()..hold = Completer<void>();
      final f = UiFixture(safety: safety)..blocked = {'fred'};
      await host(t, f);
      if (source == 'menu') {
        await t.tap(find.byKey(const Key('chatMenu')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('menuBlock')));
      } else {
        final action = t
            .widget<TextButton>(find.widgetWithText(TextButton, 'Unblock'))
            .onPressed!;
        action();
        action();
      }
      await settleUi(t);
      expect(safety.unblocks, ['fred']);
      safety.hold!.complete();
      await settleUi(t);
    });
  }
  for (final action in ['block', 'report']) {
    testWidgets(
      'incoming request $action reaches the correct contact and chat',
      (t) async {
        final safety = RecordingSafety();
        final f = UiFixture(safety: safety);
        f.chat.summaries = [
          ChatSummary(
            'alice_fred',
            'fred',
            fixtureTime,
            initiator: 'fred',
            accepted: false,
          ),
        ];
        await host(t, f);
        await t.ensureVisible(find.byKey(Key('${action}Request')));
        await t.tap(find.byKey(Key('${action}Request')));
        await t.pumpAndSettle();
        if (action == 'block') {
          await t.tap(find.byKey(const Key('confirmBlock')));
          await t.pumpAndSettle();
          expect(safety.blocks, ['fred']);
        } else {
          expect(find.byKey(const Key('reportInclude')), findsOneWidget);
          await t.ensureVisible(find.byKey(const Key('sendReport')));
          await t.tap(find.byKey(const Key('sendReport')));
          await settleUi(t);
          expect(safety.reports, [('fred', 'alice_fred')]);
        }
      },
    );
  }
  testWidgets('Dismiss removes the send error without clearing the draft', (
    t,
  ) async {
    final f = UiFixture()..chat.sendError = ChatException('Send refused');
    await host(t, f);
    await send(t);
    expect(find.text('Send refused'), findsOneWidget);
    await t.tap(find.text('Dismiss'));
    await t.pump();
    expect(find.text('Send refused'), findsNothing);
    expect(
      t.widget<TextField>(find.byKey(const Key('composer'))).controller!.text,
      'hello',
    );
  });
  testWidgets('history error retry invalidates the messages provider', (
    t,
  ) async {
    var calls = 0;
    final f = UiFixture();
    await customHost(t, f, [
      messagesProvider('alice_fred').overrideWith((ref) {
        calls++;
        return calls == 1
            ? Stream.error(StateError('history'))
            : Stream.value(<LocalMessage>[]);
      }),
    ]);
    expect(find.text('Could not load history'), findsOneWidget);
    await t.tap(find.text('Try again'));
    await settleUi(t);
    expect(calls, 2);
    expect(find.text('Could not load history'), findsNothing);
  });
}
