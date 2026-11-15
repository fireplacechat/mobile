// The screens of starting fresh with a wait (decision 0063).
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/account/takeover.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/account/lost_phone_wait_screen.dart';
import 'package:fireplace/src/view/account/takeover_alert.dart';
import 'package:fireplace/src/view/devices/new_device_screen.dart';
import 'package:fireplace/src/view/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/account_fixture.dart';
import '../../support/ui_fixture.dart';

Future<void> host(
  WidgetTester t,
  UiFixture f,
  Widget screen, {
  List<Override> extra = const [],
}) async {
  addTearDown(f.session.close);
  await t.pumpWidget(
    ProviderScope(
      overrides: [...f.overrides, ...extra],
      child: MaterialApp(theme: fireplaceTheme(Brightness.light), home: screen),
    ),
  );
  await settleUi(t);
}

/// Lets a pushed page or a sheet finish moving.
Future<void> flush(WidgetTester t) async {
  for (var i = 0; i < 3; i++) {
    await t.pump(const Duration(milliseconds: 350));
    await settleUi(t);
  }
}

PendingStart inThreeDays() => PendingStart(
  startedAt: fixtureTime,
  readyAt: fixtureTime.add(const Duration(days: 3)),
);

void main() {
  test('a day within the week is named; a later one is dated', () {
    final sunday = DateTime(2026, 10, 4, 12);
    expect(dayLabel(sunday.add(const Duration(days: 3)), sunday), 'Wednesday');
    expect(dayLabel(sunday.add(const Duration(days: 1)), sunday), 'Monday');
    expect(
      dayLabel(sunday.add(const Duration(days: 14)), sunday),
      '18 October',
    );
  });

  testWidgets('a waiting start is shown over what the person was doing, once, '
      'and "It\'s me" only puts it away', (t) async {
    final f = UiFixture();
    await host(
      t,
      f,
      const TakeoverGuard(
        uid: 'alice',
        child: Scaffold(body: Text('conversations')),
      ),
    );
    expect(find.byType(TakeoverAlertScreen), findsNothing);
    f.takeover.waiting = inThreeDays();
    await flush(t);
    expect(
      find.text('A new phone is taking over your account'),
      findsOneWidget,
    );
    expect(find.text('It takes over on Wednesday.'), findsOneWidget);
    await t.tap(find.byKey(const Key('takeoverIsMe')));
    await flush(t);
    expect(find.byType(TakeoverAlertScreen), findsNothing);
    expect(find.text('conversations'), findsOneWidget);
    // Nothing was stopped, and the same start is not shown twice.
    expect(f.takeover.stops, 0);
    expect(f.takeover.waiting, isNotNull);
    await flush(t);
    expect(find.byType(TakeoverAlertScreen), findsNothing);
  });

  testWidgets('"Stop them" asks for the password and a new one, and says when '
      'it is stopped', (t) async {
    final f = UiFixture()..takeover.waiting = inThreeDays();
    await host(t, f, const TakeoverAlertScreen(uid: 'alice'));
    await t.tap(find.byKey(const Key('stopTakeover')));
    await flush(t);
    expect(find.text('They know your password. Choose a new one.'), findsOne);

    // Refused: the words are shown and nothing is stopped.
    f.takeover.error = TakeoverException('That password is not right.');
    await t.enterText(find.byKey(const Key('stopPassword')), 'wrong-pass');
    await t.enterText(find.byKey(const Key('stopNewPassword')), 'fresh-pass-1');
    await t.tap(find.byKey(const Key('stopConfirm')));
    await flush(t);
    expect(find.text('That password is not right.'), findsOneWidget);
    expect(f.takeover.stops, 0);

    f.takeover.error = null;
    await t.tap(find.byKey(const Key('stopConfirm')));
    await flush(t);
    expect(f.takeover.stops, 1);
    expect(find.text('Stopped'), findsOneWidget);
    expect(find.byKey(const Key('stopTakeover')), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('a new phone asks once, then shows when it will be ready; '
      'Cancel withdraws', (t) async {
    final f = UiFixture();
    final recovery = ActionRecovery()..device = f.session.device;
    await host(
      t,
      f,
      const NewDeviceScreen(uid: 'alice'),
      extra: [recoveryServiceProvider.overrideWithValue(recovery)],
    );
    await t.ensureVisible(find.byKey(const Key('optReset')));
    await t.tap(find.byKey(const Key('optReset')));
    await flush(t);
    expect(find.text('Start fresh?'), findsOneWidget);
    expect(find.text('Your account will be ready in 3 days.'), findsOneWidget);
    await t.tap(find.byKey(const Key('confirmStartFresh')));
    await flush(t);
    // Asked for, not done.
    expect(f.takeover.starts, 1);
    expect(recovery.resets, 0);
    expect(find.text('Ready on Wednesday'), findsOneWidget);
    expect(find.text('Your other devices can stop this.'), findsOneWidget);
    expect(find.byKey(const Key('finishStartFresh')), findsNothing);

    await t.tap(find.byKey(const Key('withdrawStartFresh')));
    await flush(t);
    expect(f.takeover.withdrawals, 1);
    expect(find.byKey(const Key('optReset')), findsOneWidget);
  });

  testWidgets('when the wait is over the new phone can start fresh', (t) async {
    final f = UiFixture()
      ..takeover.waiting = PendingStart(
        startedAt: fixtureTime.subtract(const Duration(days: 3)),
        readyAt: fixtureTime,
      );
    final recovery = ActionRecovery()..device = f.session.device;
    await host(
      t,
      f,
      const NewDeviceScreen(uid: 'alice'),
      extra: [recoveryServiceProvider.overrideWithValue(recovery)],
    );
    expect(find.text('Ready'), findsOneWidget);
    await t.tap(find.byKey(const Key('finishStartFresh')));
    await flush(t);
    expect(recovery.resets, 1);
    expect(t.takeException(), isNull);
  });

  testWidgets('an account without a device starts fresh as before, with no '
      'wait', (t) async {
    final f = UiFixture()..takeover.devices = false;
    final recovery = ActionRecovery()..device = f.session.device;
    await host(
      t,
      f,
      const NewDeviceScreen(uid: 'alice'),
      extra: [recoveryServiceProvider.overrideWithValue(recovery)],
    );
    await t.ensureVisible(find.byKey(const Key('optReset')));
    await t.tap(find.byKey(const Key('optReset')));
    await flush(t);
    expect(find.text('Your account will be ready in 3 days.'), findsNothing);
    await t.tap(find.byKey(const Key('confirmReset')));
    await flush(t);
    expect(f.takeover.starts, 0);
    expect(recovery.resets, 1);
  });

  testWidgets('the wait is chosen from five lengths', (t) async {
    LostPhoneWait? picked;
    final f = UiFixture();
    await host(
      t,
      f,
      Scaffold(
        body: LostPhoneWaitTile(
          wait: LostPhoneWait.threeDays,
          onChanged: (w) => picked = w,
        ),
      ),
    );
    expect(find.text('3 days'), findsOneWidget);
    await t.tap(find.byKey(const Key('lostPhoneWait')));
    await flush(t);
    for (final label in ['1 day', '3 days', '1 week', '2 weeks', '30 days']) {
      expect(find.text(label), findsOneWidget);
    }
    await t.tap(find.byKey(const Key('wait_14')));
    await flush(t);
    expect(picked, LostPhoneWait.twoWeeks);
  });

  testWidgets('Settings shows the wait and saves a new one through this '
      'device', (t) async {
    final f = UiFixture()..takeover.chosen = LostPhoneWait.oneWeek;
    await host(t, f, const SettingsScreen());
    await t.scrollUntilVisible(
      find.byKey(const Key('lostPhoneWait')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await flush(t);
    expect(find.text('1 week'), findsOneWidget);
    await t.tap(find.byKey(const Key('lostPhoneWait')));
    await flush(t);
    await t.tap(find.byKey(const Key('wait_30')));
    await flush(t);
    expect(f.takeover.chosen, LostPhoneWait.thirtyDays);
    expect(find.text('30 days'), findsOneWidget);
  });
}
