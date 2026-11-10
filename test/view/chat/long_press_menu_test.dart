import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/model/chat/message_limits.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:fireplace/src/view/chat/forward/forward_message.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

class Safety extends FixtureSafety {
  final reports = <(ReportReason, String?, List<String>)>[];
  @override
  Future<void> report({
    required String peerUid,
    required ReportReason reason,
    String? chatId,
    String? note,
    List<String> context = const [],
  }) async => reports.add((reason, note, List.of(context)));
}

Future<void> openChat(WidgetTester t, UiFixture f) async {
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
}

Finder bubble(String id) => find.byKey(ValueKey('messageBubble-$id'));
Finder action(String id) => find.byKey(ValueKey('messageAction-$id'));

void main() {
  testWidgets('no per-message "..." button, and the bubble is compact', (
    t,
  ) async {
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    await f.chat.store.add(
      message(
        id: 'one',
        body: 'Hi',
        at: fixtureTime.add(const Duration(minutes: 1)),
      ),
    );
    await openChat(t, f);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey &&
            '${(w.key as ValueKey).value}'.startsWith('messageMenu-'),
      ),
      findsNothing,
    );
    // One short line: padding 16 + text about 22 + gap + time about 16, well under the old 95.
    expect(t.getSize(bubble('one')).height, lessThan(70));
  });

  testWidgets(
    'press and hold opens Copy, Forward, Info, Pin and Delete on their message',
    (t) async {
      final f = UiFixture(safety: Safety());
      await f.seed();
      addTearDown(f.session.close);
      await f.chat.store.add(
        message(
          id: 'theirs',
          body: 'from fred',
          at: fixtureTime.add(const Duration(minutes: 1)),
        ),
      );
      await openChat(t, f);
      await t.longPress(bubble('theirs'));
      await t.pumpAndSettle();
      for (final id in ['copy', 'forward', 'info', 'pin', 'delete']) {
        expect(action(id), findsOneWidget, reason: id);
      }
      expect(action('report'), findsNothing);
      expect(action('selectText'), findsNothing);
    },
  );

  testWidgets('your own message has no Report entry', (t) async {
    final f = UiFixture(safety: Safety());
    await f.seed();
    addTearDown(f.session.close);
    await f.chat.store.add(
      message(
        id: 'mine',
        body: 'from me',
        outgoing: true,
        at: fixtureTime.add(const Duration(minutes: 1)),
      ),
    );
    await openChat(t, f);
    await t.longPress(bubble('mine'));
    await t.pumpAndSettle();
    expect(action('copy'), findsOneWidget);
    expect(action('forward'), findsOneWidget);
    expect(action('report'), findsNothing);
    expect(action('delete'), findsOneWidget);
  });

  testWidgets('right click opens the same menu on desktop', (t) async {
    final f = UiFixture(safety: Safety());
    await f.seed();
    addTearDown(f.session.close);
    await f.chat.store.add(
      message(
        id: 'theirs',
        body: 'from fred',
        at: fixtureTime.add(const Duration(minutes: 1)),
      ),
    );
    await openChat(t, f);
    await t.tap(bubble('theirs'), buttons: kSecondaryButton);
    await t.pumpAndSettle();
    expect(action('copy'), findsOneWidget);
  });

  testWidgets('Info shows when the message arrived and no delivery state', (
    t,
  ) async {
    final f = UiFixture(safety: Safety());
    await f.seed();
    addTearDown(f.session.close);
    await f.chat.store.add(
      message(
        id: 'fmt',
        body: '**bold** words',
        at: fixtureTime.add(const Duration(minutes: 1)),
      ),
    );
    await openChat(t, f);
    await t.longPress(bubble('fmt'));
    await t.pumpAndSettle();
    await t.tap(action('info'));
    await t.pumpAndSettle();
    expect(find.text('Info'), findsOneWidget);
    expect(find.text('Received'), findsOneWidget);
    expect(find.textContaining('Delivered'), findsNothing);
    expect(find.textContaining('Read'), findsNothing);
  });

  testWidgets('deleting their message removes it on this device only', (
    t,
  ) async {
    final f = UiFixture(safety: Safety());
    await f.seed();
    addTearDown(f.session.close);
    await f.chat.store.add(
      message(
        id: 'bad',
        body: 'the offending text',
        at: fixtureTime.add(const Duration(minutes: 1)),
      ),
    );
    await openChat(t, f);
    await t.longPress(bubble('bad'));
    await t.pumpAndSettle();
    expect(action('report'), findsNothing);
    await t.tap(action('delete'));
    await t.pumpAndSettle();
    expect(find.text('Delete for Everyone'), findsNothing);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(await f.chat.store.get('alice_fred', 'bad'), isNotNull);
    await t.longPress(bubble('bad'));
    await t.pumpAndSettle();
    await t.tap(action('delete'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('confirmDeleteForMe')));
    await t.pumpAndSettle();
    expect(await f.chat.store.get('alice_fred', 'bad'), isNull);
    expect(bubble('bad'), findsNothing);
    expect(f.chat.remoteDeletes, isEmpty);
  });

  testWidgets('the actions are also offered to screen readers', (t) async {
    final f = UiFixture(safety: Safety());
    await f.seed();
    addTearDown(f.session.close);
    await f.chat.store.add(
      message(
        id: 'theirs',
        body: 'from fred',
        at: fixtureTime.add(const Duration(minutes: 1)),
      ),
    );
    final handle = t.ensureSemantics();
    await openChat(t, f);
    final data = t.getSemantics(bubble('theirs')).getSemanticsData();
    expect(data.hasAction(SemanticsAction.customAction), isTrue);
    handle.dispose();
  });

  testWidgets(
    'a message over the limit from another client is clipped until Show all',
    (t) async {
      final f = UiFixture(safety: Safety());
      await f.seed();
      addTearDown(f.session.close);
      final huge = 'x' * (maxMessageCharacters + 500);
      await f.chat.store.add(
        message(
          id: 'huge',
          body: huge,
          at: fixtureTime.add(const Duration(minutes: 1)),
        ),
      );
      await openChat(t, f);
      await t.ensureVisible(find.byKey(const ValueKey('showAll-huge')));
      expect(find.byKey(const ValueKey('showAll-huge')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('showAll-huge')));
      await t.pump();
      expect(find.text('Show less'), findsOneWidget);
    },
  );

  testWidgets('typing stops at the limit; the counter appears near it', (
    t,
  ) async {
    final f = UiFixture(safety: Safety());
    await f.seed();
    addTearDown(f.session.close);
    await openChat(t, f);
    expect(find.byKey(const Key('messageCounter')), findsNothing);
    await t.enterText(
      find.byKey(const Key('composer')),
      'a' * ((maxMessageCharacters * .9).floor() + 5),
    );
    await t.pump();
    expect(find.byKey(const Key('messageCounter')), findsOneWidget);
    await t.enterText(
      find.byKey(const Key('composer')),
      '😀' * (maxMessageCharacters + 100),
    );
    await t.pump();
    final text = t
        .widget<TextField>(find.byKey(const Key('composer')))
        .controller!
        .text;
    expect(messageCharacters(text), maxMessageCharacters);
    expect(find.text('$maxMessageCharacters / 16,384'), findsOneWidget);
  });

  testWidgets('a message over the limit cannot be forwarded', (t) async {
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    await t.pumpWidget(
      ProviderScope(
        overrides: f.overrides,
        child: MaterialApp(
          theme: fireplaceTheme(Brightness.light),
          home: ForwardMessageScreen(
            message: message(
              id: 'big',
              body: 'y' * (maxMessageCharacters + 1),
              outgoing: true,
            ),
          ),
        ),
      ),
    );
    await settleUi(t);
    expect(find.textContaining('cannot be forwarded'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('forwardRecipient-alice_bob')),
      findsOneWidget,
    );
    expect(
      t.widget<FilledButton>(find.byKey(const Key('forwardSend'))).onPressed,
      isNull,
    );
  });
}
