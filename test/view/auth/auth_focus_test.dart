// REVIEW R05: while signing in, the fields are frozen; after a FAILED attempt the user should still be
// in the password field with the keyboard up. On b01a65d `enabled: false` drops focus (the keyboard
// closes and the user has to tap the field again).
import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/view/auth/auth_screen.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuth extends Fake implements FirebaseAuth {}

class SlowFailingAuth extends AuthService {
  SlowFailingAuth() : super(_FakeAuth(), FakeFirebaseFirestore());
  final gate = Completer<void>();
  int calls = 0;
  @override
  Future<User> signIn({
    required String username,
    required String password,
  }) async {
    calls++;
    await gate.future;
    throw AuthException('That username or password is not right.');
  }
}

void main() {
  testWidgets('after a failed sign-in the password field is still focused', (
    t,
  ) async {
    t.view.physicalSize = const Size(800, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final auth = SlowFailingAuth();
    await t.pumpWidget(
      ProviderScope(
        overrides: [authServiceProvider.overrideWithValue(auth)],
        child: MaterialApp(
          theme: fireplaceTheme(Brightness.light),
          home: const AuthScreen(),
        ),
      ),
    );
    await t.enterText(find.byKey(const Key('username')), 'alice');
    await t.enterText(
      find.byKey(const Key('password')),
      'long-enough-password',
    );
    await t.tap(find.byKey(const Key('password')));
    await t.pump();
    await t.tap(find.byKey(const Key('submit')));
    await t.pump();
    // busy: the form is frozen but nothing may be editable or double-submittable
    await t.tap(find.byKey(const Key('submit')), warnIfMissed: false);
    await t.pump();
    expect(
      auth.calls,
      1,
      reason: 'a second tap while busy must not sign in twice',
    );
    auth.gate.complete();
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    expect(
      find.text('That username or password is not right.'),
      findsOneWidget,
    );
    expect(
      t.testTextInput.isVisible,
      isTrue,
      reason: 'the input connection is restored after failure',
    );
    final field = t.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('password')),
        matching: find.byType(EditableText),
      ),
    );
    expect(
      field.focusNode.hasFocus,
      isTrue,
      reason: 'the user should not have to tap the password field again (keyboard stays up)',
    );
  });

  testWidgets('while busy the fields cannot be edited', (t) async {
    t.view.physicalSize = const Size(800, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final auth = SlowFailingAuth();
    await t.pumpWidget(
      ProviderScope(
        overrides: [authServiceProvider.overrideWithValue(auth)],
        child: MaterialApp(
          theme: fireplaceTheme(Brightness.light),
          home: const AuthScreen(),
        ),
      ),
    );
    await t.enterText(find.byKey(const Key('username')), 'alice');
    await t.enterText(
      find.byKey(const Key('password')),
      'long-enough-password',
    );
    await t.tap(find.byKey(const Key('submit')));
    await t.pump();
    final user = t.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('username')),
        matching: find.byType(TextField),
      ),
    );
    expect(
      user.enabled != false && !user.readOnly,
      isFalse,
      reason: 'the username must be frozen (disabled or read-only) while busy',
    );
    auth.gate.complete();
    await t.pump(const Duration(milliseconds: 50));
  });
}
