// A terminal auth-stream error must never be a dead end (review: "loading-screen recovery"), and the
// splash must never clip a long message on a short screen at a large text size.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/app.dart';
import 'package:fireplace/src/styles/brand/lockup.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

class _FakeAuth extends Fake implements FirebaseAuth {}

class SignOutRecorder extends AuthService {
  SignOutRecorder() : super(_FakeAuth(), FakeFirebaseFirestore());
  int signOuts = 0;
  bool failSignOut = false;
  @override
  Future<void> signOut() async {
    signOuts++;
    if (failSignOut) throw StateError('offline');
  }
}

Future<void> settle(WidgetTester t, {int rounds = 8}) async {
  for (var i = 0; i < rounds; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await t.pump();
  }
}

Widget app(List<Override> overrides, {double textScale = 1}) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    theme: fireplaceTheme(Brightness.light),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: const AuthGate(),
  ),
);

void main() {
  testWidgets(
    'a terminal auth-stream error offers Try again, which re-subscribes and recovers',
    (t) async {
      t.view.physicalSize = const Size(400, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      var subscriptions = 0;
      await t.pumpWidget(
        app([
          authUserProvider.overrideWith((ref) {
            subscriptions++;
            return subscriptions == 1
                ? Stream<User?>.error(StateError('auth stream died'))
                : Stream<User?>.value(null);
          }),
        ]),
      );
      await settle(t);
      expect(find.byKey(const Key('authRetry')), findsOneWidget);
      expect(find.byKey(const Key('authSignOut')), findsOneWidget);
      expect(
        find.textContaining('could not check your sign-in'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('submit')),
        findsNothing,
        reason: 'not signed in yet',
      );

      await t.tap(find.byKey(const Key('authRetry')));
      await settle(t);
      expect(
        subscriptions,
        2,
        reason: 'the provider was invalidated and read again',
      );
      expect(find.byKey(const Key('authRetry')), findsNothing);
      expect(
        find.byKey(const Key('submit')),
        findsOneWidget,
        reason: 'the sign-in screen is back',
      );
    },
  );

  testWidgets(
    'Sign out clears the stuck state even if signing out itself fails, then re-reads the state',
    (t) async {
      t.view.physicalSize = const Size(400, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      var subscriptions = 0;
      final auth = SignOutRecorder()..failSignOut = true;
      await t.pumpWidget(
        app([
          authServiceProvider.overrideWithValue(auth),
          authUserProvider.overrideWith((ref) {
            subscriptions++;
            return subscriptions == 1
                ? Stream<User?>.error(StateError('auth stream died'))
                : Stream<User?>.value(null);
          }),
        ]),
      );
      await settle(t);
      await t.tap(find.byKey(const Key('authSignOut')));
      await settle(t);
      expect(auth.signOuts, 1);
      expect(subscriptions, 2);
      expect(find.byKey(const Key('submit')), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'a long error on a 320x480 screen at 200% text is scrollable, never clipped, and the buttons stay reachable',
    (t) async {
      t.view.physicalSize = const Size(320, 480);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final long = List.filled(
        12,
        'The sign-in service did not answer in time.',
      ).join(' ');
      await t.pumpWidget(
        app([
          authUserProvider.overrideWith(
            (ref) => Stream<User?>.error(StateError(long)),
          ),
        ], textScale: 2),
      );
      await settle(t);
      expect(t.takeException(), isNull, reason: 'no layout overflow');
      final scroll = t.state<ScrollableState>(
        find.descendant(
          of: find.byKey(const Key('splashScroll')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(
        scroll.position.maxScrollExtent,
        greaterThan(0),
        reason: 'the message is longer than the space, so it scrolls',
      );
      // The message area stays inside the screen.
      final area = t.getRect(find.byKey(const Key('splashScroll')));
      expect(area.bottom, lessThanOrEqualTo(480));
      expect(area.top, greaterThanOrEqualTo(0));
      // Scroll to the bottom: the action buttons come fully into view.
      await t.ensureVisible(find.byKey(const Key('authRetry')));
      await t.pump();
      expect(
        t.getRect(find.byKey(const Key('authRetry'))).bottom,
        lessThanOrEqualTo(480),
      );
      await t.ensureVisible(find.byKey(const Key('authSignOut')));
      await t.pump();
      expect(
        t.getRect(find.byKey(const Key('authSignOut'))).bottom,
        lessThanOrEqualTo(480),
      );
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'normal loading keeps only the centered lockup without a status card',
    (t) async {
      t.view.physicalSize = const Size(800, 1200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        const MaterialApp(
          home: FireplaceSplash(message: 'Preparing your keys…'),
        ),
      );
      await t.pump();
      expect(find.text('Preparing your keys…'), findsNothing);
      expect(find.byKey(const Key('splashScroll')), findsNothing);
      expect(find.byType(FireplaceLockup), findsOneWidget);
      expect(t.getCenter(find.byType(FireplaceLockup)), const Offset(400, 600));
    },
  );
}
