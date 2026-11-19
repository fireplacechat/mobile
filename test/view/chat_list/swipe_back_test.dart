// Issue 236: on Android, Settings and Invite friends can be dragged back to
// the chat list as on iOS. The page follows the finger, a short drag settles
// back, a long one returns to the list, and vertical scrolling still works.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/src/app/invite_providers.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat_list/chat_list_screen.dart';
import 'package:fireplace/src/view/invites/invite_screen.dart';
import 'package:fireplace/src/view/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

const width = 400.0;

Future<void> openList(WidgetTester t, TargetPlatform platform) async {
  final db = FakeFirebaseFirestore();
  final fixture = UiFixture();
  await t.runAsync(
    () => db.doc('users/alice').set({
      'username': 'alice',
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 11, 14)),
    }),
  );
  t.view.physicalSize = const Size(width, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  addTearDown(fixture.session.close);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        ...fixture.overrides,
        firestoreProvider.overrideWithValue(db),
        inviteClockProvider.overrideWithValue(
          () => DateTime.utc(2026, 11, 14, 12),
        ),
      ],
      child: MaterialApp(
        theme: fireplaceTheme(Brightness.light).copyWith(platform: platform),
        home: const ChatListScreen(),
      ),
    ),
  );
  await settleUi(t);
}

/// Drags right from the middle of the page, without letting go.
Future<TestGesture> dragRight(WidgetTester t, double distance) async {
  final gesture = await t.startGesture(const Offset(width / 2, 400));
  for (var moved = 0.0; moved < distance; moved += 20) {
    await gesture.moveBy(const Offset(20, 0));
    await t.pump(const Duration(milliseconds: 16));
  }
  return gesture;
}

void main() {
  for (final (name, button, page) in [
    ('Settings', 'settings', SettingsScreen),
    ('Invite friends', 'inviteFriends', InviteScreen),
  ]) {
    group(name, () {
      Future<void> open(WidgetTester t) async {
        await openList(t, TargetPlatform.android);
        await t.tap(find.byKey(Key(button)));
        await t.pumpAndSettle();
        expect(find.byType(page), findsOneWidget);
      }

      testWidgets('the page follows the finger and a long drag goes back', (
        t,
      ) async {
        await open(t);
        final gesture = await dragRight(t, 160);
        // Under the finger, with the chat list showing beside it.
        expect(t.getTopLeft(find.byType(page)).dx, closeTo(160, 30));
        expect(find.byType(ChatListScreen), findsOneWidget);
        for (var i = 0; i < 4; i++) {
          await gesture.moveBy(const Offset(20, 0));
          await t.pump(const Duration(milliseconds: 16));
        }
        await gesture.up();
        await t.pumpAndSettle();
        expect(find.byType(page), findsNothing);
        expect(find.byType(ChatListScreen), findsOneWidget);
      });

      testWidgets('a short drag settles back into place', (t) async {
        await open(t);
        final gesture = await dragRight(t, 60);
        // Hold still, so letting go is not a fling.
        await t.pump(const Duration(milliseconds: 300));
        await gesture.up();
        await t.pumpAndSettle();
        expect(find.byType(page), findsOneWidget);
        expect(t.getTopLeft(find.byType(page)).dx, 0);
      });

      testWidgets('a quick flick goes back', (t) async {
        await open(t);
        await t.flingFrom(
          const Offset(width / 2, 400),
          const Offset(80, 0),
          800,
        );
        await t.pumpAndSettle();
        expect(find.byType(page), findsNothing);
      });

      testWidgets('dragging up and down does not go back', (t) async {
        await open(t);
        await t.dragFrom(const Offset(width / 2, 600), const Offset(0, -300));
        await t.pumpAndSettle();
        await t.dragFrom(const Offset(width / 2, 300), const Offset(0, 300));
        await t.pumpAndSettle();
        expect(find.byType(page), findsOneWidget);
        expect(t.getTopLeft(find.byType(page)).dx, 0);
      });
    });
  }

  testWidgets('on iOS the page keeps the system edge swipe only', (t) async {
    await openList(t, TargetPlatform.iOS);
    await t.tap(find.byKey(const Key('settings')));
    await t.pumpAndSettle();
    final gesture = await dragRight(t, 260);
    await gesture.up();
    await t.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });
}
