import 'package:fireplace/src/model/settings/licence_catalog.dart';
import 'package:fireplace/src/view/settings/licences_screen.dart';
import 'package:fireplace/src/view/settings/settings_screen.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';
import '../../support/licence_fixture.dart';

void main() {
  testWidgets('Settings opens licences and returns without losing the page', (
    tester,
  ) async {
    final fixture = UiFixture();
    addTearDown(fixture.session.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...fixture.overrides,
          licenceCatalogProvider.overrideWith((_) => fixtureLicences()),
        ],
        child: MaterialApp(
          theme: fireplaceTheme(Brightness.light),
          home: const SettingsScreen(),
        ),
      ),
    );
    await settleUi(tester);
    // About is the last section; the list builds rows as they scroll in.
    await tester.scrollUntilVisible(
      find.byKey(const Key('openLicences')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('openLicences')));
    await tester.pumpAndSettle();
    expect(find.byType(LicencesScreen), findsOneWidget);
    expect(find.byType(LicensePage), findsNothing);
    expect(find.text('example_clock, example_parser'), findsOneWidget);
    await tester.tap(find.text('example_clock, example_parser'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fullLicenceText')), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });
}
