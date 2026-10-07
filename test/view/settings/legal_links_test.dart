// REVIEW R08: the privacy policy and terms must be reachable INSIDE the app (App Store guideline 5.1.1 asks for
// a privacy-policy link in the app; Play asks for the same for apps that handle personal data). On b01a65d
// Settings has no such entry and the sign-up sentence is plain, non-interactive text. This asks for a
// package-free solution (show the address, selectable, with a Copy link button); opening it in a browser
// needs `url_launcher` and is left to the owner's decision on new packages.
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
  expect(find.text(privacyUrl), findsOneWidget);
  expect(find.text(termsUrl), findsOneWidget);
  expect(find.text('Privacy policy'), findsWidgets);
  expect(find.text('Terms of use'), findsWidgets);
}

void main() {
  testWidgets('Settings has a legal entry that shows both addresses', (
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
    'Copy link puts the exact address on the clipboard and confirms it',
    (t) async {
      t.view.physicalSize = const Size(800, 3000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      String? copied;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
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
      await t.tap(find.byKey(const Key('copyLink-privacy')));
      await t.pump(const Duration(milliseconds: 100));
      expect(copied, privacyUrl);
      expect(find.text('Link copied'), findsOneWidget);
      await t.tap(find.byKey(const Key('copyLink-terms')));
      await t.pump(const Duration(milliseconds: 100));
      expect(copied, termsUrl);
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
