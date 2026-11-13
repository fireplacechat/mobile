import 'package:fireplace/src/model/notifications/preview_diagnostics.dart';
import 'package:fireplace/src/view/settings/preview_diagnostics_screen.dart';
import 'package:fireplace/src/view/settings/settings_screen.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('fireplace/notifications');
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  testWidgets('shows only bounded numeric local results and can refresh', (
    tester,
  ) async {
    var reads = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'previewDiagnostics');
          reads++;
          return [
            {
              'at': 1700000000000,
              'ms': 450,
              'peak': 11 * 1024 * 1024,
              'outcome': 1,
            },
            {'body': 'fictional content that must not be displayed'},
          ];
        });
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: PreviewDiagnosticsScreen())),
    );
    await tester.pumpAndSettle();
    expect(find.text('Preview · 11.00 MB · 450 ms'), findsOneWidget);
    expect(
      find.text('fictional content that must not be displayed'),
      findsNothing,
    );
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(reads, 2);
  });

  test('invalid or unbounded records are not displayed', () {
    final valid = {
      'at': 1700000000000,
      'ms': 450,
      'peak': 11 * 1024 * 1024,
      'outcome': 1,
    };
    expect(PreviewDiagnosticRun.parse(valid), isNotNull);
    for (final replacement in [
      {'ms': -1},
      {'ms': 60001},
      {'peak': 'fictional text'},
      {'outcome': 4},
      {'at': 0},
      {'peak': 1024 * 1024 * 1024},
    ]) {
      expect(PreviewDiagnosticRun.parse({...valid, ...replacement}), isNull);
    }
  });

  testWidgets('test builds open diagnostics through the hidden long press', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fixture = UiFixture();
    addTearDown(fixture.session.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...fixture.overrides,
          previewDiagnosticRunsProvider.overrideWith((_) async => []),
        ],
        child: MaterialApp(
          theme: fireplaceTheme(Brightness.light),
          home: const SettingsScreen(),
        ),
      ),
    );
    await settleUi(tester);
    await tester.ensureVisible(find.byKey(const Key('openPrivacyPolicy')));
    await tester.longPress(find.byKey(const Key('openPrivacyPolicy')));
    await tester.pumpAndSettle();
    expect(find.text('Preview test results'), findsOneWidget);
    expect(find.text('No preview runs recorded yet.'), findsOneWidget);
  });
}
