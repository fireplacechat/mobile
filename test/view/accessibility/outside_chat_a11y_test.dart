import 'dart:ui';

import 'package:fireplace/src/view/account/account_deletion_screens.dart';
import 'package:fireplace/src/view/auth/auth_screen.dart';
import 'package:fireplace/src/view/devices/devices_screen.dart';
import 'package:fireplace/src/view/devices/link_new_device_screen.dart';
import 'package:fireplace/src/view/devices/new_device_screen.dart';
import 'package:fireplace/src/view/devices/recovery_entry_screen.dart';
import 'package:fireplace/src/view/recovery/recovery_key_screen.dart';
import 'package:fireplace/src/view/settings/chat_appearance.dart';
import 'package:fireplace/src/view/settings/legal_links.dart';
import 'package:fireplace/src/view/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/accessibility_matrix.dart';
import '../../support/ui_fixture.dart';

/// Labels, 48px targets, and no overflow at 2x text on a 320px-wide screen.
Future<void> check(
  WidgetTester t,
  String name,
  Widget screen, {
  bool signUp = false,
}) async {
  final f = UiFixture();
  await f.seed();
  addTearDown(f.session.close);
  final semantics = t.ensureSemantics();
  try {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await pump(t, f, screen, Brightness.light, 2, 0);
    if (signUp) {
      await t.ensureVisible(find.byKey(const Key('toggle')));
      await t.tap(find.byKey(const Key('toggle')));
      await settleUi(t);
    }
    expect(t.takeException(), isNull, reason: name);
    await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(t, meetsGuideline(androidTapTargetGuideline));
  } finally {
    semantics.dispose();
  }
}

/// A control below the fold is not built until the list scrolls to it.
Future<void> reveal(WidgetTester t, Finder finder) async {
  final target = finder;
  for (var i = 0; i < 8 && target.evaluate().isEmpty; i++) {
    await t.drag(find.byType(Scrollable).first, const Offset(0, -280));
    await t.pump();
  }
  await t.ensureVisible(target);
}

void main() {
  testWidgets('settings controls are labeled and large text fits', (t) async {
    await check(t, 'settings', const SettingsScreen());
    final soundFinder = find.byKey(const Key('sendSound'), skipOffstage: false);
    await reveal(t, soundFinder);
    final sound = t.getSemantics(soundFinder).getSemanticsData();
    expect(sound.label, contains('Send sound'));
    expect(sound.flagsCollection.isToggled, Tristate.isTrue);
    expect(t.getSize(soundFinder).shortestSide, greaterThanOrEqualTo(48));
    final previewFinder = find.byKey(
      const Key('notificationPreviews'),
      skipOffstage: false,
    );
    await reveal(t, previewFinder);
    final previews = t.getSemantics(previewFinder).getSemanticsData();
    expect(previews.label, contains('In-App Notifications'));
    expect(previews.flagsCollection.isToggled, isNot(Tristate.none));
    final theme = find.byKey(const Key('themeMode'), skipOffstage: false);
    await reveal(t, theme);
    await t.tap(theme);
    await t.pumpAndSettle();
    final choice = find.byKey(
      const ValueKey<String>('theme-light'),
      skipOffstage: false,
    );
    expect(choice, findsOneWidget);
    expect(t.getSize(choice).height, greaterThanOrEqualTo(48));
    await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(t, meetsGuideline(androidTapTargetGuideline));
  });

  testWidgets('sign-in controls are labeled and large text fits', (t) async {
    await check(t, 'sign-in', const AuthScreen());
    expect(find.byTooltip('Show password'), findsOneWidget);
  });

  testWidgets('sign-up controls are labeled and large text fits', (t) async {
    await check(t, 'sign-up', const AuthScreen(), signUp: true);
    await t.ensureVisible(find.byKey(const Key('age16'), skipOffstage: false));
    final age = t
        .getSemantics(find.byKey(const Key('age16')))
        .getSemanticsData();
    expect(age.label, contains('I am 16 or older'));
    expect(age.flagsCollection.isChecked, CheckedState.isFalse);
    expect(
      t.getSize(find.byKey(const Key('age16'))).shortestSide,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('recovery key screen is labeled and large text fits', (t) async {
    await check(t, 'recovery', const RecoveryKeyScreen());
  });

  testWidgets('link a device is labeled and large text fits', (t) async {
    await check(t, 'link', const LinkNewDeviceScreen());
  });

  testWidgets('new device screen is labeled and large text fits', (t) async {
    await check(t, 'new device', const NewDeviceScreen(uid: 'alice'));
  });

  testWidgets('restore screen is labeled and large text fits', (t) async {
    await check(t, 'restore', const RecoveryEntryScreen(uid: 'alice'));
  });

  testWidgets('devices screen is labeled and large text fits', (t) async {
    await check(t, 'devices', const DevicesScreen());
    final remove = find.byTooltip('Remove device', skipOffstage: false);
    await reveal(t, remove);
    expect(find.text('This device', skipOffstage: false), findsOneWidget);
    expect(t.getSize(remove).shortestSide, greaterThanOrEqualTo(48));
  });

  testWidgets('delete account is labeled and large text fits', (t) async {
    await check(t, 'delete', const DeleteAccountScreen());
  });

  testWidgets('chat colors are labeled and large text fits', (t) async {
    await check(t, 'colors', const ChatAppearanceScreen());
  });

  testWidgets('legal links are labeled and large text fits', (t) async {
    await check(t, 'legal', const LegalLinksScreen());
    final privacy = find.byTooltip(
      'Copy privacy policy link',
      skipOffstage: false,
    );
    final terms = find.byTooltip('Copy terms of use link', skipOffstage: false);
    await reveal(t, privacy);
    await reveal(t, terms);
    expect(t.getSize(privacy).shortestSide, greaterThanOrEqualTo(48));
    expect(t.getSize(terms).shortestSide, greaterThanOrEqualTo(48));
  });
}
