// Issue 239: the New chat panel can be dragged down to close. It follows
// the finger, a short drag settles back, a longer or quicker one closes it,
// and a scrolled list first scrolls back to the top.
import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat_list/chat_list_screen.dart';
import 'package:fireplace/src/view/chat_list/new_chat_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

final title = find.text('New chat');
final list = find.byKey(const Key('newChatList'));

Future<void> openPanel(
  WidgetTester t, {
  TargetPlatform platform = TargetPlatform.android,
  int extraPeople = 0,
}) async {
  final f = UiFixture();
  await f.seed();
  addTearDown(f.session.close);
  f.chat.summaries = [
    ...f.chat.summaries,
    for (var i = 0; i < extraPeople; i++)
      ChatSummary(
        'alice_person$i',
        'person$i',
        fixtureTime.subtract(Duration(days: 2, minutes: i)),
      ),
  ];
  t.view.physicalSize = const Size(400, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ProviderScope(
      overrides: f.overrides,
      child: MaterialApp(
        theme: fireplaceTheme(Brightness.light).copyWith(platform: platform),
        home: const ChatListScreen(),
      ),
    ),
  );
  await settleUi(t);
  await t.tap(find.byKey(const Key('newChat')));
  await t.pumpAndSettle();
  expect(find.byType(NewChatSheet), findsOneWidget);
}

/// Drags down on the list without letting go, slowly.
Future<TestGesture> dragDown(WidgetTester t, double distance) async {
  final gesture = await t.startGesture(t.getCenter(list));
  for (var moved = 0.0; moved < distance; moved += 20) {
    await gesture.moveBy(const Offset(0, 20));
    await t.pump(const Duration(milliseconds: 16));
  }
  return gesture;
}

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    group(platform.name, () {
      testWidgets('the panel follows the finger, then closes', (t) async {
        await openPanel(t, platform: platform);
        final top = t.getTopLeft(title).dy;
        final gesture = await dragDown(t, 300);
        expect(t.getTopLeft(title).dy, closeTo(top + 300, 40));
        // The chat list shows above the panel.
        expect(find.byType(ChatListScreen), findsOneWidget);
        // On, well past halfway.
        for (var i = 0; i < 12; i++) {
          await gesture.moveBy(const Offset(0, 20));
          await t.pump(const Duration(milliseconds: 16));
        }
        await t.pump(const Duration(milliseconds: 300));
        await gesture.up();
        await t.pumpAndSettle();
        expect(find.byType(NewChatSheet), findsNothing);
      });

      testWidgets('a short drag settles back into place', (t) async {
        await openPanel(t, platform: platform);
        final top = t.getTopLeft(title).dy;
        final gesture = await dragDown(t, 120);
        await t.pump(const Duration(milliseconds: 300));
        await gesture.up();
        await t.pumpAndSettle();
        expect(find.byType(NewChatSheet), findsOneWidget);
        expect(t.getTopLeft(title).dy, top);
      });

      testWidgets('a quick flick down closes it', (t) async {
        await openPanel(t, platform: platform);
        await t.fling(list, const Offset(0, 150), 1500);
        await t.pumpAndSettle();
        expect(find.byType(NewChatSheet), findsNothing);
      });

      testWidgets('a scrolled list scrolls back to the top first', (t) async {
        await openPanel(t, platform: platform, extraPeople: 30);
        final top = t.getTopLeft(title).dy;
        await t.drag(list, const Offset(0, -400));
        await t.pumpAndSettle();
        expect(find.byKey(const Key('contact_fred')), findsNothing);

        // Down by less than it scrolled: the list moves, the panel does not.
        final gesture = await dragDown(t, 200);
        expect(t.getTopLeft(title).dy, top);
        await t.pump(const Duration(milliseconds: 300));
        await gesture.up();
        await t.pumpAndSettle();
        expect(find.byType(NewChatSheet), findsOneWidget);

        // Back at the top, the next drag pulls the panel down.
        await t.drag(list, const Offset(0, 400));
        await t.pumpAndSettle();
        expect(find.byKey(const Key('contact_fred')), findsOneWidget);
        final again = await dragDown(t, 160);
        expect(t.getTopLeft(title).dy, greaterThan(top + 100));
        await again.up();
        await t.pumpAndSettle();
      });
    });
  }
}
