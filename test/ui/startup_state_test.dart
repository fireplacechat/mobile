import 'package:firebase_auth/firebase_auth.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/services/key_service.dart';
import 'package:fireplace/src/ui/account_deletion_screens.dart';
import 'package:fireplace/src/ui/app.dart';
import 'package:fireplace/src/ui/new_device_screen.dart';
import 'package:fireplace/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/ui_fixture.dart';

class _User extends Fake implements User {
  @override
  String get uid => 'alice';
}

void main() {
  for (final error in [
    NeedsRecoveryException(),
    AccountDeletionPending('alice'),
  ]) {
    testWidgets('startup preserves special routing for ${error.runtimeType}', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            authUserProvider.overrideWith((ref) => Stream.value(_User())),
            appSessionProvider.overrideWith((ref) async => throw error),
          ],
          child: MaterialApp(
            theme: fireplaceTheme(Brightness.light),
            home: const AuthGate(),
          ),
        ),
      );
      await settleUi(tester);
      expect(
        error is NeedsRecoveryException
            ? find.byType(NewDeviceScreen)
            : find.byType(DeleteAccountScreen),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'session failure hides internals and retry can load an existing session',
    (tester) async {
      final fixture = UiFixture(overrideAuth: false);
      addTearDown(fixture.session.close);
      var attempts = 0;
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            ...fixture.overrides.skip(1),
            authUserProvider.overrideWith((ref) => Stream.value(_User())),
            appSessionProvider.overrideWith((ref) async {
              if (++attempts == 1) throw StateError('private local diagnostic');
              return fixture.session;
            }),
          ],
          child: MaterialApp(
            theme: fireplaceTheme(Brightness.light),
            home: const AuthGate(),
          ),
        ),
      );
      await settleUi(tester);
      expect(find.textContaining('private local diagnostic'), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('retrySession')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('retrySession')));
      await settleUi(tester);
      expect(attempts, 2);
      expect(find.byKey(const Key('newChat')), findsOneWidget);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
