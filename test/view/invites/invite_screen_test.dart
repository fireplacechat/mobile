import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/src/app/invite_providers.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/invites/invite_service.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/invites/invite_screen.dart';
import 'package:fireplace/src/view/invites/invite_ticket.dart';
import 'package:fireplace/src/view/settings/settings_screen.dart';
import 'package:fireplace/src/view/chat_list/chat_list_screen.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

final created = DateTime.utc(2026, 11, 14, 12);

class _RefusingService extends InviteService {
  _RefusingService(super.db);
  int attempts = 0;
  @override
  Future<void> create(String uid, int row) async {
    attempts++;
    throw InviteException(
      'This invite is not ready yet, or invites are paused.',
    );
  }
}

class _Page {
  _Page(this.t);
  final WidgetTester t;
  final db = FakeFirebaseFirestore();
  final fixture = UiFixture();
  DateTime now = created;
  InviteService? service;

  Future<void> open({Widget home = const InviteScreen()}) async {
    await t.runAsync(
      () => db.doc('users/alice').set({
        'username': 'alice',
        'createdAt': Timestamp.fromDate(created),
      }),
    );
    t.view.physicalSize = const Size(800, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    addTearDown(fixture.session.close);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          ...fixture.overrides,
          firestoreProvider.overrideWithValue(db),
          inviteClockProvider.overrideWithValue(() => now),
          if (service != null)
            inviteServiceProvider.overrideWithValue(service!),
        ],
        child: MaterialApp(theme: fireplaceTheme(Brightness.light), home: home),
      ),
    );
    await settleUi(t);
  }

  /// Moves the clock on and lets the countdown tick.
  Future<void> wait(Duration d) async {
    now = now.add(d);
    await t.pump(const Duration(seconds: 1));
  }
}

String? clipboard;
void mockClipboard(WidgetTester t) {
  clipboard = null;
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String;
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
}

void main() {
  test('countdowns read as days and a clock', () {
    expect(
      inviteCountdown(
        const Duration(days: 6, hours: 23, minutes: 14, seconds: 8),
      ),
      '6d 23:14:08',
    );
    expect(inviteCountdown(const Duration(hours: 5)), '05:00:00');
    expect(inviteCountdown(const Duration(seconds: -3)), '00:00:00');
    expect(
      inviteCountdownLabel(const Duration(days: 1, hours: 2, minutes: 3)),
      '1 day, 2 hours',
    );
    expect(inviteCountdownLabel(const Duration(minutes: 1)), '1 minute');
  });

  testWidgets('three rows: one ready, two counting down', (t) async {
    final p = _Page(t);
    await p.open();
    expect(find.byKey(const Key('createInvite0')), findsOneWidget);
    expect(find.byKey(const Key('createInvite1')), findsNothing);
    expect(find.byKey(const Key('createInvite2')), findsNothing);
    expect(find.text('1d 00:00:00'), findsOneWidget);
    expect(find.text('7d 00:00:00'), findsOneWidget);

    await p.wait(const Duration(seconds: 1));
    expect(find.text('23:59:59'), findsOneWidget);
    expect(find.text('6d 23:59:59'), findsOneWidget);

    // When the countdown ends, the row can make a code.
    await p.wait(const Duration(days: 1));
    expect(find.byKey(const Key('createInvite1')), findsOneWidget);
    expect(find.byKey(const Key('inviteCountdown1')), findsNothing);
  });

  testWidgets('a code is made, shown and copied with dashes', (t) async {
    mockClipboard(t);
    final p = _Page(t);
    await p.open();
    await t.tap(find.byKey(const Key('createInvite0')));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await settleUi(t);
    final code = t.widget<Text>(find.byKey(const Key('inviteCode0'))).data!;
    expect(code, matches(RegExp(r'^[A-Z2-7]{4}(-[A-Z2-7]{4}){3}$')));
    expect(find.text('Unused'), findsOneWidget);

    await t.tap(find.byKey(const Key('copyInvite0')));
    await t.pump();
    expect(clipboard, code);
    expect(find.text('Invite code copied'), findsOneWidget);
  });

  testWidgets('a refused create shows plain words and is not retried', (
    t,
  ) async {
    final p = _Page(t);
    final service = _RefusingService(p.db);
    p.service = service;
    await p.open();
    await t.tap(find.byKey(const Key('createInvite0')));
    await settleUi(t);
    expect(find.byKey(const Key('inviteError')), findsOneWidget);
    expect(find.textContaining('not ready yet'), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
    expect(service.attempts, 1);
    expect(find.byKey(const Key('inviteCode0')), findsNothing);
  });

  testWidgets('replacing asks first and waits an hour after a swap', (t) async {
    final p = _Page(t);
    p.now = created.add(const Duration(days: 8));
    await p.open();
    await t.tap(find.byKey(const Key('createInvite0')));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await settleUi(t);
    final first = t.widget<Text>(find.byKey(const Key('inviteCode0'))).data;

    await t.tap(find.byKey(const Key('replaceInvite0')));
    await t.pumpAndSettle();
    expect(find.text('Replace this code?'), findsOneWidget);
    await t.tap(find.byKey(const Key('confirmReplaceInvite')));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await settleUi(t);
    expect(
      t.widget<Text>(find.byKey(const Key('inviteCode0'))).data,
      isNot(first),
    );
    // The fake store has no server clock, so set the swap time the rules saw.
    await t.runAsync(
      () => p.db.doc('users/alice/inviteSlots/0').update({
        'replacedAt': Timestamp.fromDate(p.now),
      }),
    );
    await settleUi(t);
    final replace = t.widget<TextButton>(
      find.byKey(const Key('replaceInvite0')),
    );
    expect(replace.onPressed, isNull);
    expect(find.textContaining('replace it again in'), findsOneWidget);
  });

  testWidgets('a used code says Used and never who used it', (t) async {
    final p = _Page(t);
    await t.runAsync(() async {
      await p.db.doc('users/alice/inviteSlots/0').set({
        'code': 'ABCDEFGHIJKLMNOP',
        'invite': 'h',
        'at': Timestamp.fromDate(created),
        'used': true,
      });
      await p.db.doc('invites/h').set({
        'by': 'alice',
        'slot': 0,
        'usedBy': 'bob',
      });
      await p.db.doc('users/bob').set({'username': 'bob'});
    });
    await p.open();
    expect(find.text('Used'), findsOneWidget);
    expect(find.byKey(const Key('copyInvite0')), findsNothing);
    expect(find.byKey(const Key('replaceInvite0')), findsNothing);
    expect(find.textContaining('bob'), findsNothing);
    expect(find.textContaining('@'), findsNothing);
  });

  testWidgets('when the operator pauses invites, nothing can be made', (
    t,
  ) async {
    final p = _Page(t);
    await t.runAsync(
      () => p.db.doc('config/invites').set({
        'unlockAfter': [0, 0, 0, 0],
        'paused': true,
      }),
    );
    await p.open();
    expect(find.byKey(const Key('invitesPaused')), findsOneWidget);
    for (var i = 0; i < 4; i++) {
      final b = t.widget<FilledButton>(find.byKey(Key('createInvite$i')));
      expect(b.onPressed, isNull);
    }
  });

  testWidgets('a new row from the operator appears without reopening', (
    t,
  ) async {
    final p = _Page(t);
    await p.open();
    expect(find.byKey(const Key('inviteTicket3')), findsNothing);
    await t.runAsync(
      () => p.db.doc('inviteAllowances/alice').set({
        'unlockAfter': [0, 0, 0, 0],
      }),
    );
    await settleUi(t);
    expect(find.byKey(const Key('createInvite3')), findsOneWidget);
  });

  testWidgets('the + on the chat list opens invites; the arrow goes back', (
    t,
  ) async {
    final p = _Page(t);
    await p.open(home: const ChatListScreen());
    final plus = find.byKey(const Key('inviteFriends'));
    expect(plus, findsOneWidget);
    // The circle takes the theme accent (Ember by default).
    final button = t.widget<IconButton>(plus);
    final context = t.element(plus);
    expect(
      button.style!.backgroundColor!.resolve({}),
      FireplaceUiTokens.of(context).accent,
    );
    await t.tap(plus);
    await t.pumpAndSettle();
    expect(find.byType(InviteScreen), findsOneWidget);
    // Slides in from the left: no back arrow on the left, one on the right.
    expect(find.byType(BackButton), findsNothing);
    await t.tap(find.byKey(const Key('inviteBack')));
    await t.pumpAndSettle();
    expect(find.byType(InviteScreen), findsNothing);
    expect(find.byType(ChatListScreen), findsOneWidget);
  });

  testWidgets('Settings no longer lists invites', (t) async {
    final p = _Page(t);
    await p.open(home: const SettingsScreen());
    expect(find.text('Invite friends'), findsNothing);
  });

  testWidgets('with no invites the page says so', (t) async {
    final p = _Page(t);
    await t.runAsync(
      () => p.db.doc('config/invites').set({'unlockAfter': <int>[]}),
    );
    await p.open();
    expect(find.byKey(const Key('noInvites')), findsOneWidget);
    expect(find.byType(InviteTicket), findsNothing);
  });
}
