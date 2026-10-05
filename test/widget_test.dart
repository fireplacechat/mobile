import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/ui/app.dart';
import 'package:fireplace/src/ui/logo.dart';
import 'package:fireplace/src/ui/lockup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app() => ProviderScope(
  overrides: [authUserProvider.overrideWith((_) => Stream.value(null))],
  child: const FireplaceApp(),
);

void main() {
  testWidgets('signed-out users see the branded sign-in screen', (t) async {
    await t.pumpWidget(app());
    await t.pumpAndSettle();
    expect(find.byType(FireplaceLogo), findsOneWidget);
    expect(find.byType(FireplaceWordmark), findsOneWidget);
    expect(
      t
          .widget<Semantics>(
            find
                .descendant(
                  of: find.byType(FireplaceWordmark),
                  matching: find.byType(Semantics),
                )
                .first,
          )
          .properties
          .label,
      'fireplace.',
    );
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('New here? Create an account'), findsOneWidget);
  });

  testWidgets('form validates username and password; toggles to sign-up', (
    t,
  ) async {
    await t.pumpWidget(app());
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('submit')));
    await t.pumpAndSettle();
    expect(find.text('3-20 characters: a-z, 0-9, _'), findsOneWidget);
    expect(find.text('At least 8 characters'), findsOneWidget);

    await t.tap(find.byKey(const Key('toggle')));
    await t.pumpAndSettle();
    expect(find.text('Create account'), findsOneWidget);
    expect(find.textContaining('no email reset'), findsOneWidget);
  });

  testWidgets('renders in dark mode too', (t) async {
    t.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(t.platformDispatcher.clearAllTestValues);
    await t.pumpWidget(app());
    await t.pumpAndSettle();
    expect(find.byType(FireplaceLogo), findsOneWidget);
  });

  testWidgets('sign-up asks for an invite code and rejects a malformed one', (
    t,
  ) async {
    await t.pumpWidget(app());
    await t.pumpAndSettle();
    expect(
      find.byKey(const Key('invite')),
      findsNothing,
    ); // sign-in has no invite field
    await t.tap(find.byKey(const Key('toggle')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('invite')), findsOneWidget);
    await t.enterText(find.byKey(const Key('username')), 'alice');
    await t.enterText(find.byKey(const Key('password')), 'correct horse');
    await t.enterText(find.byKey(const Key('invite')), 'not-a-code');
    // Sign-up needs the 16+ declaration before the button does anything.
    await t.ensureVisible(find.byKey(const Key('age16')));
    await t.tap(find.byKey(const Key('age16')));
    await t.pump();
    await t.ensureVisible(find.byKey(const Key('submit')));
    await t.tap(find.byKey(const Key('submit')));
    await t.pumpAndSettle();
    expect(
      find.text('Enter the 16-character invite code you were given'),
      findsOneWidget,
    );
    await t.ensureVisible(find.byKey(const Key('toggle')));
    await t.pump();
    await t.tap(find.byKey(const Key('toggle'))); // back to sign-in hides it
    await t.pumpAndSettle();
    expect(find.byKey(const Key('invite')), findsNothing);
  });
}
