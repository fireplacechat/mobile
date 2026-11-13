import 'package:fireplace/src/app.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/styles/brand/lockup.dart';
import 'package:fireplace/src/view/auth/auth_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/support/ui_fixture.dart';
import 'catalog_case.dart';

final startupCases = <CatalogCase>[
  for (final ready in [false, true])
    CatalogCase(
      ready ? 'startup-minimum-ready' : 'startup-minimum-visible',
      const AuthGate(),
      overrideAuth: false,
      overrides: [authUserProvider.overrideWith((ref) => Stream.value(null))],
      act: (tester, fixture) async {
        // The catalog advances another 400 ms immediately before capture:
        // the visible case is captured at 2.5 s, and the ready case at 3.4 s.
        await tester.pump(
          ready
              ? const Duration(seconds: 3)
              : const Duration(milliseconds: 2100),
        );
        await settleUi(tester);
        expect(
          find.byType(FireplaceSplash),
          ready ? findsNothing : findsOneWidget,
        );
        expect(find.byType(AuthScreen), ready ? findsOneWidget : findsNothing);
      },
    ),
];
