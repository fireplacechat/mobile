import 'package:fireplace/src/view/account/account_deletion_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'catalog_case.dart';

List<CatalogCase> accountDeletionCases() => [
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) ...[
    CatalogCase(
      'account-deletion-${platform.name}',
      const DeleteAccountScreen(),
      platform: platform,
      size: const Size(375, 812),
      padding: const EdgeInsets.only(top: 44, bottom: 34),
    ),
    CatalogCase(
      'account-deletion-confirm-${platform.name}',
      const DeleteAccountScreen(),
      platform: platform,
      size: const Size(375, 812),
      padding: const EdgeInsets.only(top: 44, bottom: 34),
      act: (t, _) async {
        await t.scrollUntilVisible(
          find.byKey(const Key('deleteAccount')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await t.ensureVisible(find.byKey(const Key('deleteAccount')));
        await t.pumpAndSettle();
      },
    ),
    CatalogCase(
      'account-deletion-resume-${platform.name}',
      const DeleteAccountScreen(resume: true),
      platform: platform,
      size: const Size(375, 812),
      padding: const EdgeInsets.only(top: 44, bottom: 34),
    ),
  ],
];
