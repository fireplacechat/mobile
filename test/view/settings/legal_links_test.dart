// Settings and sign-up reach the shared browser-link page before opening a URL.
import 'package:fireplace/src/view/auth/auth_screen.dart';
import 'package:fireplace/src/view/settings/settings_screen.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

const privacyUrl = 'https://fireplacechat.com/privacy/';
const termsUrl = 'https://fireplacechat.com/terms/';

void expectBothLinks() {
  expect(find.byKey(const Key('openPrivacyPolicy')), findsOneWidget);
  expect(find.byKey(const Key('openTermsOfUse')), findsOneWidget);
  expect(find.text('Privacy policy'), findsWidgets);
  expect(find.text('Terms of use'), findsWidgets);
}

void main() {
  testWidgets('Settings has a legal entry with both browser buttons', (
    t,
  ) async {
    t.view.physicalSize = const Size(800, 3000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final f = UiFixture();
    addTearDown(f.session.close);
    await t.pumpWidget(
      ProviderScope(
        overrides: f.overrides,
        child: MaterialApp(
          theme: fireplaceTheme(Brightness.light),
          home: const SettingsScreen(),
        ),
      ),
    );
    await settleUi(t);
    await t.ensureVisible(find.byKey(const Key('legalLinks')));
    await t.tap(find.byKey(const Key('legalLinks')));
    await settleUi(t);
    expectBothLinks();
  });

  testWidgets(
    'the Settings legal buttons open the exact addresses in the browser',
    (t) async {
      t.view.physicalSize = const Size(800, 3000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      String? opened;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('fireplace/browser'),
        (call) async {
          if (call.method == 'open') {
            opened = call.arguments as String;
          }
          return true;
        },
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('fireplace/browser'),
          null,
        ),
      );
      final f = UiFixture();
      addTearDown(f.session.close);
      await t.pumpWidget(
        ProviderScope(
          overrides: f.overrides,
          child: MaterialApp(
            theme: fireplaceTheme(Brightness.light),
            home: const SettingsScreen(),
          ),
        ),
      );
      await settleUi(t);
      await t.ensureVisible(find.byKey(const Key('legalLinks')));
      await t.tap(find.byKey(const Key('legalLinks')));
      await settleUi(t);
      await t.pump(
        const Duration(milliseconds: 600),
      ); // let the page finish sliding in
      await t.tap(find.byKey(const Key('openPrivacyPolicy')));
      await t.pump(const Duration(milliseconds: 100));
      expect(opened, privacyUrl);
      expect(find.text('Link copied'), findsNothing);
      await t.tap(find.byKey(const Key('openTermsOfUse')));
      await t.pump(const Duration(milliseconds: 100));
      expect(opened, termsUrl);
    },
  );

  testWidgets(
    'the sign-up screen offers the same links before an account is created',
    (t) async {
      t.view.physicalSize = const Size(800, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: fireplaceTheme(Brightness.light),
            home: const AuthScreen(),
          ),
        ),
      );
      expect(
        find.byKey(const Key('legalLinks')),
        findsNothing,
        reason: 'sign-in mode does not need it',
      );
      await t.tap(find.byKey(const Key('toggle')));
      await t.pump();
      await t.ensureVisible(find.byKey(const Key('legalLinks')));
      await t.tap(find.byKey(const Key('legalLinks')));
      await t.pumpAndSettle();
      expectBothLinks();
    },
  );
}
