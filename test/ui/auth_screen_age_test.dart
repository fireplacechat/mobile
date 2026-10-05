import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/ui/auth_screen.dart';
import 'package:fireplace/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuth extends Fake implements FirebaseAuth {}

class _FakeUser extends Fake implements User {}

/// Records calls instead of talking to Firebase.
class RecordingAuth extends AuthService {
  RecordingAuth() : super(_FakeAuth(), FakeFirebaseFirestore());
  final signUps = <String>[];
  final signIns = <String>[];
  Completer<User>? hold;

  @override
  Future<User> signUp({
    required String username,
    required String password,
    required String inviteCode,
    String? displayName,
  }) {
    signUps.add(username);
    return hold?.future ?? Future.value(_FakeUser());
  }

  @override
  Future<User> signIn({required String username, required String password}) {
    signIns.add(username);
    return hold?.future ?? Future.value(_FakeUser());
  }
}

Future<RecordingAuth> pumpAuth(WidgetTester t, {double textScale = 1}) async {
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final auth = RecordingAuth();
  await t.pumpWidget(
    ProviderScope(
      overrides: [authServiceProvider.overrideWithValue(auth)],
      child: MaterialApp(
        theme: fireplaceTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const AuthScreen(),
      ),
    ),
  );
  return auth;
}

Future<void> toSignUp(WidgetTester t) async {
  await t.tap(find.byKey(const Key('toggle')));
  await t.pump();
}

Future<void> fill(WidgetTester t) async {
  await t.enterText(find.byKey(const Key('username')), 'alice');
  await t.enterText(find.byKey(const Key('password')), 'a-long-password');
  await t.enterText(find.byKey(const Key('invite')), 'ABCD-EFGH-JKLM-NPQR');
  await t.pump();
}

void main() {
  testWidgets('sign-in mode has no age box and signing in is unaffected', (
    t,
  ) async {
    final auth = await pumpAuth(t);
    expect(find.byKey(const Key('age16')), findsNothing);
    await t.enterText(find.byKey(const Key('username')), 'alice');
    await t.enterText(find.byKey(const Key('password')), 'a-long-password');
    await t.tap(find.byKey(const Key('submit')));
    await t.pump();
    expect(auth.signIns, ['alice']);
    expect(auth.signUps, isEmpty);
  });

  testWidgets(
    'sign-up shows an unchecked "I am 16 or older" and a disabled button',
    (t) async {
      await pumpAuth(t);
      await toSignUp(t);
      expect(find.text('I am 16 or older'), findsOneWidget);
      expect(
        t.widget<CheckboxListTile>(find.byKey(const Key('age16'))).value,
        isFalse,
      );
      expect(
        t.widget<FilledButton>(find.byKey(const Key('submit'))).onPressed,
        isNull,
      );
      expect(find.byKey(const Key('betaNotice')), findsOneWidget);
      // The notice never asks for, or mentions, a date of birth.
      expect(find.textContaining('birth'), findsNothing);
    },
  );

  testWidgets(
    'keyboard submission without the declaration makes no sign-up call and explains why',
    (t) async {
      final auth = await pumpAuth(t);
      await toSignUp(t);
      await fill(t);
      await t.showKeyboard(find.byKey(const Key('password')));
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();
      expect(auth.signUps, isEmpty, reason: 'zero Auth writes while unchecked');
      expect(find.byKey(const Key('age16Error')), findsOneWidget);
      expect(
        find.text('You must be 16 or older to join this beta.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'ticking the box clears the error, enables the button and signs up once',
    (t) async {
      final auth = await pumpAuth(t);
      await toSignUp(t);
      await fill(t);
      await t.showKeyboard(find.byKey(const Key('password')));
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();
      expect(find.byKey(const Key('age16Error')), findsOneWidget);

      await t.tap(find.byKey(const Key('age16')));
      await t.pump();
      expect(find.byKey(const Key('age16Error')), findsNothing);
      expect(
        t.widget<FilledButton>(find.byKey(const Key('submit'))).onPressed,
        isNotNull,
      );

      await t.tap(find.byKey(const Key('submit')));
      await t.pump();
      expect(auth.signUps, ['alice']);
    },
  );

  testWidgets('switching modes resets the declaration and the error', (
    t,
  ) async {
    await pumpAuth(t);
    await toSignUp(t);
    await t.tap(find.byKey(const Key('age16')));
    await t.pump();
    expect(
      t.widget<CheckboxListTile>(find.byKey(const Key('age16'))).value,
      isTrue,
    );
    await t.tap(find.byKey(const Key('toggle'))); // back to sign-in
    await t.pump();
    await toSignUp(t);
    expect(
      t.widget<CheckboxListTile>(find.byKey(const Key('age16'))).value,
      isFalse,
    );
    expect(find.byKey(const Key('age16Error')), findsNothing);
  });

  testWidgets('while signing up the checkbox is disabled (busy state)', (
    t,
  ) async {
    final auth = await pumpAuth(t);
    auth.hold = Completer<User>();
    await toSignUp(t);
    await fill(t);
    await t.tap(find.byKey(const Key('age16')));
    await t.pump();
    await t.tap(find.byKey(const Key('submit')));
    await t.pump();
    expect(
      t.widget<CheckboxListTile>(find.byKey(const Key('age16'))).onChanged,
      isNull,
    );
    auth.hold!.complete(_FakeUser());
    await t.pump();
  });

  testWidgets('the notice and the checkbox stay usable at 200% text size', (
    t,
  ) async {
    await pumpAuth(t, textScale: 2);
    await toSignUp(t);
    await t.pump();
    expect(t.takeException(), isNull, reason: 'no overflow at 200%');
    expect(find.byKey(const Key('age16')), findsOneWidget);
    expect(find.byKey(const Key('betaNotice')), findsOneWidget);
  });
  testWidgets('pending sign-in freezes inputs and guards repeated submission', (
    t,
  ) async {
    final auth = await pumpAuth(t);
    auth.hold = Completer<User>();
    await t.enterText(find.byKey(const Key('username')), 'alice');
    await t.enterText(find.byKey(const Key('password')), 'a-long-password');
    await t.tap(find.byKey(const Key('submit')));
    await t.pump();
    // Frozen while busy: read-only (not disabled) so the field keeps focus and the keyboard.
    for (final field in ['username', 'password']) {
      expect(
        t
            .widget<TextField>(
              find.descendant(
                of: find.byKey(Key(field)),
                matching: find.byType(TextField),
              ),
            )
            .readOnly,
        isTrue,
        reason: '$field must be frozen while signing in',
      );
    }
    t
        .widget<TextField>(
          find.descendant(
            of: find.byKey(const Key('password')),
            matching: find.byType(TextField),
          ),
        )
        .onSubmitted!('ignored');
    expect(auth.signIns, ['alice']);
    auth.hold!.completeError(StateError('internal SDK detail'));
    await t.pump();
    expect(find.textContaining('internal SDK detail'), findsNothing);
    expect(
      find.text('We could not sign you in. Please try again.'),
      findsOneWidget,
    );
    expect(
      t.widget<TextFormField>(find.byKey(const Key('username'))).enabled,
      isTrue,
    );
  });

  testWidgets(
    'sign-up rejection preserves entries and completing after disposal is safe',
    (t) async {
      final auth = await pumpAuth(t);
      auth.hold = Completer<User>();
      await toSignUp(t);
      await fill(t);
      await t.tap(find.byKey(const Key('age16')));
      await t.pump();
      await t.tap(find.byKey(const Key('submit')));
      await t.pump();
      auth.hold!.completeError(
        AuthException('That invitation is unavailable.'),
      );
      await t.pump();
      expect(find.text('That invitation is unavailable.'), findsOneWidget);
      expect(
        t
            .widget<TextFormField>(find.byKey(const Key('invite')))
            .controller!
            .text,
        'ABCD-EFGH-JKLM-NPQR',
      );
      auth.hold = Completer<User>();
      await t.tap(find.byKey(const Key('submit')));
      await t.pump();
      await t.pumpWidget(const SizedBox());
      auth.hold!.complete(_FakeUser());
      await t.pump();
      expect(t.takeException(), isNull);
      expect(auth.signUps, ['alice', 'alice']);
    },
  );
}
