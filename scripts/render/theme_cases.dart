// The approved theme picker at phone and tablet sizes, reached from Settings.
import 'package:fireplace/src/view/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'catalog_case.dart';

final themeCases = <CatalogCase>[
  for (final (name, size, scale) in [
    ('phone', const Size(375, 812), 1.35),
    ('small', const Size(320, 568), 1.35),
    ('large-text', const Size(320, 640), 2.0),
    ('large-phone', const Size(430, 932), 1.35),
    ('landscape', const Size(812, 375), 1.35),
    ('tablet', const Size(768, 1024), 1.35),
    ('tablet-landscape', const Size(1024, 768), 1.35),
  ])
    CatalogCase(
      'theme-picker-$name',
      const SettingsScreen(),
      size: size,
      textScale: scale,
      padding: size.width > size.height
          ? const EdgeInsets.fromLTRB(44, 0, 44, 21)
          : const EdgeInsets.only(top: 44, bottom: 34),
      pixelRatio: 3,
      act: (tester, fixture) async {
        await tester.ensureVisible(find.byKey(const Key('themeMode')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('themeMode')));
        await tester.pumpAndSettle();
      },
    ),
];
