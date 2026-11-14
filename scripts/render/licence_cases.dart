import 'package:fireplace/src/model/settings/licence_catalog.dart';
import 'package:fireplace/src/view/settings/licences_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/support/licence_fixture.dart';
import '../../test/support/ui_fixture.dart';
import 'catalog_case.dart';

final licenceCases = <CatalogCase>[
  for (final state in [
    'groups',
    'search',
    'full',
    'narrow-large',
    'full-narrow-large',
  ])
    CatalogCase(
      'licences-$state',
      const LicencesScreen(),
      size: state.contains('narrow')
          ? const Size(320, 640)
          : const Size(390, 844),
      textScale: state.contains('narrow') ? 2 : 1,
      overrides: [
        licenceCatalogProvider.overrideWith((_) => fixtureLicences()),
      ],
      act: (tester, _) async {
        if (state != 'search' && !state.startsWith('full')) return;
        await tester.enterText(
          find.byKey(const Key('licenceSearch')),
          'parser',
        );
        await settleUi(tester);
        if (!state.startsWith('full')) return;
        final card = find.byType(Card);
        await tester.ensureVisible(card);
        await tester.tap(card);
        await tester.pumpAndSettle();
      },
    ),
];
