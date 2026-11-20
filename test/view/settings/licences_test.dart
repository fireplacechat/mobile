// The open-source licences are back under Help and about (issue 249). Until
// their own page is designed, the row opens Flutter's licence page.
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/settings/help_settings_screen.dart';
import 'package:fireplace/src/view/settings/settings_category.dart';
import 'package:fireplace/src/view/settings/settings_screen.dart';
import 'package:fireplace/src/widgets/settings/settings_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

Future<void> _open(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fixture = UiFixture();
  addTearDown(fixture.session.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: fixture.overrides,
      child: MaterialApp(theme: fireplaceTheme(Brightness.light), home: home),
    ),
  );
  await settleUi(tester);
}

void main() {
  testWidgets('Help and about has the privacy policy, terms of use and '
      'open-source licences, in that order', (tester) async {
    await _open(tester, const HelpSettingsScreen());
    final rows = tester
        .widgetList<SettingsTile>(find.byType(SettingsTile))
        .map((row) => row.title)
        .toList();
    expect(rows, ['Privacy policy', 'Terms of use', 'Open-source licences']);
    // No version: the app has no way to read it without a new plugin.
    expect(find.textContaining('Version'), findsNothing);
  });

  testWidgets('the licences row opens the licence page, and Back returns', (
    tester,
  ) async {
    await _open(tester, const SettingsScreen());
    await tester.tap(find.byKey(SettingsCategory.help.rowKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('openLicences')));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
    expect(find.text('Fireplace'), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsNothing);
    expect(find.byType(HelpSettingsScreen), findsOneWidget);
  });
}
