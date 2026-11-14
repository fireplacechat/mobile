import 'package:fireplace/src/model/common/external_browser.dart';
import 'package:fireplace/src/view/settings/settings_screen.dart';
import 'package:fireplace/src/widgets/dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'catalog_case.dart';

class _UnavailableBrowser implements ExternalBrowser {
  const _UnavailableBrowser();
  @override
  Future<bool> open(Uri url) async => false;
}

final legalCases = <CatalogCase>[
  CatalogCase(
    'settings-legal-links',
    const SettingsScreen(),
    act: (tester, fixture) async {
      await tester.scrollUntilVisible(
        find.byKey(const Key('openTermsOfUse')),
        400,
        maxScrolls: 30,
      );
      await tester.pumpAndSettle();
    },
  ),
  for (final large in [false, true])
    CatalogCase(
      'settings-legal-links-browser-unavailable${large ? '-narrow-large' : ''}',
      const SettingsScreen(),
      size: large ? const Size(320, 640) : const Size(390, 844),
      textScale: large ? 2 : 1,
      overrides: [
        externalBrowserProvider.overrideWithValue(const _UnavailableBrowser()),
      ],
      act: (tester, fixture) async {
        await tester.scrollUntilVisible(
          find.byKey(const Key('openTermsOfUse')),
          400,
          maxScrolls: 30,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('openPrivacyPolicy')));
        await tester.pumpAndSettle();
        expect(find.byType(UiDialog), findsOneWidget);
      },
    ),
  CatalogCase(
    'settings-legal-links-narrow-large',
    const SettingsScreen(),
    size: Size(320, 640),
    textScale: 2,
    act: (tester, fixture) async {
      await tester.scrollUntilVisible(
        find.byKey(const Key('openTermsOfUse')),
        400,
        maxScrolls: 30,
      );
      await tester.pumpAndSettle();
    },
  ),
];
