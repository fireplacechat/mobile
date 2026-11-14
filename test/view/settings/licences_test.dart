import 'package:fireplace/src/view/settings/settings_screen.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/widgets/settings_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

void main() {
  testWidgets('About only shows privacy policy and terms of use', (
    tester,
  ) async {
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
    await tester.scrollUntilVisible(
      find.byKey(const Key('openTermsOfUse')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final about = find.ancestor(
      of: find.text('About'),
      matching: find.byType(UiSettingsSection),
    );
    expect(
      find.descendant(of: about, matching: find.byType(ListTile)),
      findsNWidgets(2),
    );
    expect(find.byKey(const Key('openPrivacyPolicy')), findsOneWidget);
    expect(find.byKey(const Key('openTermsOfUse')), findsOneWidget);
    expect(find.byKey(const Key('openLicences')), findsNothing);
    expect(find.text('Open-source licences'), findsNothing);
  });
}
