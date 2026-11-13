import 'package:fireplace/src/model/common/external_browser.dart';
import 'package:fireplace/src/view/settings/legal_links.dart';
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
    'privacy-and-terms-browser-unavailable',
    const LegalLinksScreen(),
    overrides: [
      externalBrowserProvider.overrideWithValue(const _UnavailableBrowser()),
    ],
    act: (tester, fixture) async {
      await tester.tap(find.byKey(const Key('openPrivacyPolicy')));
      await tester.pumpAndSettle();
    },
  ),
  const CatalogCase(
    'privacy-and-terms-narrow-large',
    LegalLinksScreen(),
    size: Size(320, 640),
    textScale: 2,
  ),
];
