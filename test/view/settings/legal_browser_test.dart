import 'dart:async';

import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/settings/legal_links.dart';
import 'package:fireplace/src/view/settings/settings_screen.dart';
import 'package:fireplace/src/widgets/dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

const browserChannel = MethodChannel('fireplace/browser');
const privacy = Key('openPrivacyPolicy');
const terms = Key('openTermsOfUse');
const errorText = 'Could not open your browser. Try again.';

Future<void> openPage(
  WidgetTester tester, {
  required bool settings,
  Size size = const Size(800, 3000),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fixture = UiFixture();
  addTearDown(fixture.session.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: fixture.overrides,
      child: MaterialApp(
        theme: fireplaceTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: settings ? const SettingsScreen() : const LegalLinksScreen(),
      ),
    ),
  );
  await settleUi(tester);
}

VoidCallback? opener(WidgetTester tester, Key key, bool settings) => settings
    ? tester.widget<ListTile>(find.byKey(key)).onTap
    : tester.widget<OutlinedButton>(find.byKey(key)).onPressed;

void mockBrowser(
  WidgetTester tester,
  Future<Object?> Function(MethodCall) handler,
) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    browserChannel,
    handler,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      browserChannel,
      null,
    ),
  );
}

void main() {
  for (final settings in [false, true]) {
    group(settings ? 'Settings rows' : 'Sign-up legal page', () {
      testWidgets(
        'legal buttons open the exact existing URLs without copying',
        (tester) async {
          final opened = <String>[];
          mockBrowser(tester, (call) async {
            expect(call.method, 'open');
            opened.add(call.arguments as String);
            return true;
          });
          await openPage(tester, settings: settings);
          expect(find.byKey(privacy), findsOneWidget);
          expect(find.byKey(terms), findsOneWidget);
          expect(find.byTooltip('Copy privacy policy link'), findsNothing);
          expect(find.byTooltip('Copy terms of use link'), findsNothing);
          expect(find.byType(SelectableText), findsNothing);
          expect(find.textContaining('Copy a link'), findsNothing);
          await tester.tap(find.byKey(privacy));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(terms));
          await tester.pumpAndSettle();
          expect(opened, [
            'https://fireplacechat.com/privacy/',
            'https://fireplacechat.com/terms/',
          ]);
          expect(find.text(errorText), findsNothing);
        },
      );

      for (final failure in [false, null, 'platform', 'missing']) {
        testWidgets(
          'browser failure $failure keeps the page and allows retry',
          (tester) async {
            var fail = true;
            var attempts = 0;
            mockBrowser(tester, (call) async {
              attempts++;
              if (!fail) return true;
              if (failure == 'platform') {
                throw PlatformException(
                  code: 'blocked',
                  message: 'PRIVATE DETAIL',
                );
              }
              if (failure == 'missing') throw MissingPluginException();
              return failure;
            });
            await openPage(tester, settings: settings);
            await tester.tap(find.byKey(privacy));
            await tester.pumpAndSettle();
            expect(find.text(errorText), findsOneWidget);
            expect(find.byType(UiDialog), findsOneWidget);
            expect(
              find.descendant(
                of: find.byType(UiDialog),
                matching: find.text(errorText),
              ),
              findsOneWidget,
            );
            expect(find.textContaining('PRIVATE DETAIL'), findsNothing);
            expect(find.byKey(privacy), findsOneWidget);
            expect(find.byKey(terms), findsOneWidget);
            expect(opener(tester, privacy, settings), isNull);
            await tester.tap(find.byKey(const Key('dismissBrowserError')));
            await tester.pumpAndSettle();
            expect(find.byType(UiDialog), findsNothing);
            expect(find.text(errorText), findsNothing);
            expect(opener(tester, privacy, settings), isNotNull);
            fail = false;
            await tester.tap(find.byKey(terms));
            await tester.pumpAndSettle();
            expect(attempts, 2);
            expect(find.text(errorText), findsNothing);
          },
        );
      }

      testWidgets(
        'browser error popup stays dismissible at 200% text on a short phone',
        (tester) async {
          mockBrowser(tester, (call) async => false);
          await openPage(
            tester,
            settings: settings,
            size: const Size(320, 480),
            textScale: 2,
          );
          await tester.scrollUntilVisible(find.byKey(privacy), 300);
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(privacy));
          await tester.pumpAndSettle();
          expect(find.byType(UiDialog), findsOneWidget);
          expect(tester.takeException(), isNull);
          final dismiss = find.byKey(const Key('dismissBrowserError'));
          await tester.ensureVisible(dismiss);
          await tester.pumpAndSettle();
          expect(tester.getRect(dismiss).bottom, lessThanOrEqualTo(480));
          await tester.tap(dismiss);
          await tester.pumpAndSettle();
          expect(find.byType(UiDialog), findsNothing);
          expect(opener(tester, privacy, settings), isNotNull);
        },
      );

      testWidgets(
        'opening guards repeated taps and safely finishes after disposal',
        (tester) async {
          final hold = Completer<bool>();
          var attempts = 0;
          mockBrowser(tester, (call) {
            attempts++;
            return hold.future;
          });
          await openPage(tester, settings: settings);
          final action = opener(tester, privacy, settings)!;
          action();
          action();
          await tester.pump();
          expect(attempts, 1);
          for (final key in [privacy, terms]) {
            expect(opener(tester, key, settings), isNull);
          }
          await tester.pumpWidget(const SizedBox());
          hold.complete(false);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    });
  }
}
