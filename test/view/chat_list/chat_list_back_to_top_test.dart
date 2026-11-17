// Coming back to the chat list (issue 207): after a chat or another page
// closes, the list starts at the top again, newest conversation first.
// Closing the long-press menu keeps the place.
import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat_list/chat_list_screen.dart';
import 'package:fireplace/src/widgets/page_return_observer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';
import 'chat_tile_layout_test.dart' show row;

final _both = TargetPlatformVariant({
  TargetPlatform.android,
  TargetPlatform.iOS,
});

/// Twenty conversations, `alice_p0` the newest, so the list scrolls.
Future<void> _pump(WidgetTester t) async {
  final f = UiFixture();
  f.chat.summaries = [
    for (var i = 0; i < 20; i++)
      ChatSummary('alice_p$i', 'p$i', fixtureTime.subtract(Duration(hours: i))),
  ];
  t.view.physicalSize = const Size(375, 812);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  addTearDown(f.session.close);
  await t.pumpWidget(
    ProviderScope(
      overrides: f.overrides,
      child: MaterialApp(
        theme: fireplaceTheme(Brightness.dark),
        navigatorObservers: [pageReturnObserver],
        home: const ChatListScreen(),
      ),
    ),
  );
  await settleUi(t);
}

final _list = find.byKey(const Key('conversationList'));

double _offset(WidgetTester t) => t
    .state<ScrollableState>(
      find.descendant(of: _list, matching: find.byType(Scrollable)),
    )
    .position
    .pixels;

Future<void> _scrollDown(WidgetTester t) async {
  await t.drag(_list, const Offset(0, -600));
  await t.pumpAndSettle();
  expect(_offset(t), greaterThan(300));
  expect(row('alice_p0'), findsNothing);
}

NavigatorState _navigator(WidgetTester t) => Navigator.of(t.element(_list));

void main() {
  testWidgets('the list opens with the newest conversation at the top', (
    t,
  ) async {
    await _pump(t);
    expect(_offset(t), 0);
    expect(
      t.getRect(row('alice_p0')).top,
      lessThan(t.getRect(row('alice_p1')).top),
    );
  });

  testWidgets('closing a page over the list returns to the top', (t) async {
    await _pump(t);
    await _scrollDown(t);
    final navigator = _navigator(t);
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('A chat')),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('A chat'), findsOneWidget);
    navigator.pop();
    await t.pumpAndSettle();
    expect(_offset(t), 0);
    expect(row('alice_p0'), findsOneWidget);
  }, variant: _both);

  testWidgets('a page that opens another page returns to the top once both '
      'close', (t) async {
    await _pump(t);
    await _scrollDown(t);
    final navigator = _navigator(t);
    for (final title in ['Settings', 'Devices']) {
      navigator.push(
        MaterialPageRoute<void>(builder: (_) => Scaffold(body: Text(title))),
      );
      await t.pumpAndSettle();
    }
    navigator.pop();
    await t.pumpAndSettle();
    navigator.pop();
    await t.pumpAndSettle();
    expect(_offset(t), 0);
  });

  testWidgets('closing the long-press menu keeps the place', (t) async {
    await _pump(t);
    await _scrollDown(t);
    final before = _offset(t);
    final visible = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('conversation-alice_p'),
    );
    await t.longPress(visible.first);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('chatRowMenu')), findsOneWidget);
    Navigator.of(t.element(find.byKey(const Key('chatRowMenu')))).pop();
    await t.pumpAndSettle();
    expect(find.byKey(const Key('chatRowMenu')), findsNothing);
    expect(_offset(t), before);
  });

  group('PageReturnObserver', () {
    testWidgets('calls back only when an opaque page above the route closes', (
      t,
    ) async {
      final observer = PageReturnObserver();
      final key = GlobalKey<NavigatorState>();
      await t.pumpWidget(
        MaterialApp(
          navigatorKey: key,
          navigatorObservers: [observer],
          home: const SizedBox(),
        ),
      );
      final homeRoute = ModalRoute.of(t.element(find.byType(SizedBox)))!;
      var returns = 0;
      observer.subscribe(homeRoute, () => returns++);

      key.currentState!.push(
        PageRouteBuilder<void>(
          opaque: false,
          pageBuilder: (_, _, _) => const Text('menu'),
        ),
      );
      await t.pumpAndSettle();
      key.currentState!.pop();
      await t.pumpAndSettle();
      expect(returns, 0);

      key.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const Text('page')),
      );
      await t.pumpAndSettle();
      key.currentState!.pop();
      await t.pumpAndSettle();
      expect(returns, 1);

      observer.unsubscribe(homeRoute);
      key.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const Text('page')),
      );
      await t.pumpAndSettle();
      key.currentState!.pop();
      await t.pumpAndSettle();
      expect(returns, 1);
    });
  });
}
