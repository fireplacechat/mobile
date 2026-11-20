// Devices are named in words a person can match to a phone (issue 202); the
// id is a tap away. Settings shows a Security code row instead of hex.
import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/devices/devices_screen.dart';
import 'package:fireplace/src/view/settings/security_code_screen.dart';
import 'package:fireplace/src/view/settings/privacy_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

void main() {
  const l = DefaultMaterialLocalizations();
  final now = DateTime(2026, 11, 19, 12);

  group('deviceNames', () {
    test('this phone, and others by the day they were added', () {
      final names = deviceNames(
        [
          DeviceInfo('a', DateTime(2026, 11, 2), false, true),
          DeviceInfo('b', DateTime(2026, 11, 14, 9, 5), false, false),
          DeviceInfo('c', DateTime(2025, 3, 1), true, false),
          DeviceInfo('d', null, false, false),
        ],
        l,
        now: now,
      );
      expect(names, {
        'a': 'This phone',
        'b': 'Phone added Nov 14',
        'c': 'Phone added Mar 1, 2025',
        'd': 'Another phone',
      });
    });

    test('two added the same day also get the time', () {
      final names = deviceNames(
        [
          DeviceInfo('a', DateTime(2026, 11, 14, 9, 5), false, false),
          DeviceInfo('b', DateTime(2026, 11, 14, 18, 30), false, false),
        ],
        l,
        now: now,
      );
      expect(names['a'], 'Phone added Nov 14, 9:05 am');
      expect(names['b'], 'Phone added Nov 14, 6:30 pm');
    });
  });

  Future<void> open(WidgetTester t, Widget home) async {
    t.view.physicalSize = const Size(800, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final f = UiFixture();
    addTearDown(f.session.close);
    await t.pumpWidget(
      ProviderScope(
        overrides: f.overrides,
        child: MaterialApp(theme: fireplaceTheme(Brightness.light), home: home),
      ),
    );
    await settleUi(t);
  }

  testWidgets('Your devices names devices, not ids; a tap shows the id', (
    t,
  ) async {
    await open(t, const DevicesScreen());
    expect(find.text('This phone'), findsOneWidget);
    expect(find.textContaining('Phone added'), findsOneWidget);
    expect(find.text('example-second-device'), findsNothing);
    expect(find.text('example-device-alice'), findsNothing);
    await t.tap(find.byKey(const Key('device_example-second-device')));
    await t.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('deviceDetails')),
        matching: find.text('example-second-device'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Settings has a Security code row, not hex or a device id', (
    t,
  ) async {
    await open(t, const PrivacySettingsScreen());
    expect(find.text('Your identity fingerprint'), findsNothing);
    expect(find.text('example-device-alice'), findsNothing);
    expect(find.text('This device'), findsNothing);
    await t.tap(find.byKey(const Key('securityCode')));
    await settleUi(t);
    await t.pumpAndSettle();
    expect(find.byType(SecurityCodeScreen), findsOneWidget);
    final code = t.widget<SelectableText>(
      find.byKey(const Key('ownSecurityCode')),
    );
    expect(code.data, isNot('…'));
    expect(code.data, isNotEmpty);
  });
}
