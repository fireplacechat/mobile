import 'package:fireplace/src/ui/settings_screen.dart';
import 'package:fireplace/src/ui/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/ui_fixture.dart';

void main() {
  testWidgets('Settings opens licences and returns without losing the page', (
    tester,
  ) async {
    LicenseRegistry.addLicense(
      () => Stream.value(
        const LicenseEntryWithLineBreaks([
          'fixture-package',
        ], 'Fixture licence'),
      ),
    );
    final fixture = UiFixture();
    addTearDown(fixture.session.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: fixture.overrides,
        child: MaterialApp(
          theme: fireplaceTheme(Brightness.light),
          home: const SettingsScreen(),
        ),
      ),
    );
    await settleUi(tester);
    await tester.ensureVisible(find.byKey(const Key('openLicences')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('openLicences')));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
    expect(find.text('fireplace.'), findsOneWidget);
    expect(find.text('fixture-package'), findsOneWidget);
    await tester.tap(find.text('fixture-package'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Fixture licence', findRichText: true),
      findsOneWidget,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });
}
