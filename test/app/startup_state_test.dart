import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/keys/key_service.dart';
import 'package:fireplace/src/view/account/account_deletion_screens.dart';
import 'package:fireplace/src/app.dart';
import 'package:fireplace/src/view/devices/new_device_screen.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/styles/brand/lockup.dart';
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
    StateError('startup failed'),
  ]) {
    testWidgets(
      'session refresh hides ${error.runtimeType} actions until startup finishes',
      (tester) async {
        final resumed = Completer<AppSession?>();
        var attempts = 0;
        final container = ProviderContainer(
          retry: (_, _) => null,
          overrides: [
            authUserProvider.overrideWith((ref) => Stream.value(_User())),
            appSessionProvider.overrideWith((ref) async {
              if (++attempts == 1) throw error;
              return resumed.future;
            }),
          ],
        );
        addTearDown(() {
          container.dispose();
          if (!resumed.isCompleted) resumed.complete(null);
        });
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: fireplaceTheme(Brightness.light),
              home: const AuthGate(),
            ),
          ),
        );
        await settleUi(tester);
        expect(attempts, 1);
        final preparing = find.byWidgetPredicate(
          (widget) =>
              widget is FireplaceSplash &&
              widget.message == 'Preparing your account…' &&
              widget.actions.isEmpty,
        );
        expect(preparing, findsNothing);

        // Successful recovery/reset invalidates this provider before rebuilding
        // the session. Its old error actions must not remain usable meanwhile.
        container.invalidate(appSessionProvider);
        await tester.pump();
        await tester.pump();
        expect(attempts, 2);
        expect(find.byType(NewDeviceScreen), findsNothing);
        expect(find.byKey(const Key('optReset')), findsNothing);
        expect(find.byKey(const Key('retrySession')), findsNothing);
        expect(preparing, findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
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
