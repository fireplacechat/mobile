import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:fireplace/src/app.dart';
import 'package:fireplace/src/app/chat_list_warmup.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/styles/brand/lockup.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/auth/auth_screen.dart';
import 'package:fireplace/src/view/chat_list/chat_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../support/ui_fixture.dart';

class _User extends Fake implements User {
  @override
  String get uid => 'alice';
}

Future<void> launch(WidgetTester tester, List<Override> overrides) =>
    tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: overrides,
        child: MaterialApp(
          theme: fireplaceTheme(Brightness.light),
          home: const AuthGate(),
        ),
      ),
    );

// All durations below advance the widget test's fake clock, not wall time.
void main() {
  testWidgets('a ready sign-in screen waits exactly three seconds', (
    tester,
  ) async {
    await launch(tester, [
      authUserProvider.overrideWith((ref) => Stream.value(null)),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2999));
    expect(find.byType(FireplaceSplash), findsOneWidget);
    expect(find.byType(AuthScreen), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byType(FireplaceSplash), findsNothing);
    expect(find.byType(AuthScreen), findsOneWidget);
  });

  testWidgets('session and chat warmup start during the minimum splash', (
    tester,
  ) async {
    final fixture = UiFixture(overrideAuth: false)..hasBackup = true;
    addTearDown(fixture.session.close);
    final warmup = Completer<void>();
    var sessions = 0;
    var warmups = 0;
    await launch(tester, [
      ...fixture.overrides.skip(1),
      authUserProvider.overrideWith((ref) => Stream.value(_User())),
      appSessionProvider.overrideWith((ref) async {
        sessions++;
        return fixture.session;
      }),
      chatListWarmupProvider.overrideWith((ref) {
        warmups++;
        return warmup.future;
      }),
    ]);
    await settleUi(tester);
    expect(sessions, 1);
    expect(warmups, 1);
    await tester.pump(const Duration(milliseconds: 500));
    warmup.complete();
    await settleUi(tester);
    await tester.pump(const Duration(milliseconds: 2499));
    expect(find.byType(FireplaceSplash), findsOneWidget);
    expect(find.byType(ChatListScreen), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byType(ChatListScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a slow account opens when ready without another three seconds', (
    tester,
  ) async {
    final fixture = UiFixture(overrideAuth: false)..hasBackup = true;
    addTearDown(fixture.session.close);
    final session = Completer<AppSession?>();
    await launch(tester, [
      ...fixture.overrides.skip(1),
      authUserProvider.overrideWith((ref) => Stream.value(_User())),
      appSessionProvider.overrideWith((ref) => session.future),
      chatListWarmupProvider.overrideWith((ref) async {}),
    ]);
    await settleUi(tester);
    await tester.pump(const Duration(seconds: 5));
    expect(find.byType(FireplaceSplash), findsOneWidget);
    session.complete(fixture.session);
    await settleUi(tester);
    expect(find.byType(FireplaceSplash), findsNothing);
    expect(find.byType(ChatListScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('navigation, resume and sign-out do not replay the minimum', (
    tester,
  ) async {
    final fixture = UiFixture(overrideAuth: false)..hasBackup = true;
    addTearDown(fixture.session.close);
    final users = StreamController<User?>();
    addTearDown(users.close);
    await launch(tester, [
      ...fixture.overrides,
      authUserProvider.overrideWith((ref) => users.stream),
      chatListWarmupProvider.overrideWith((ref) async {}),
    ]);
    users.add(_User());
    await settleUi(tester);
    await tester.pump(const Duration(seconds: 3));
    await settleUi(tester);
    expect(find.byType(ChatListScreen), findsOneWidget);
    final navigator = Navigator.of(tester.element(find.byType(ChatListScreen)));
    unawaited(
      navigator.push<void>(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('Other page')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    navigator.pop();
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byType(ChatListScreen), findsOneWidget);
    users.add(null);
    await settleUi(tester);
    expect(find.byType(AuthScreen), findsOneWidget);
    expect(find.byType(FireplaceSplash), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('startup errors stay actionable before the minimum expires', (
    tester,
  ) async {
    await launch(tester, [
      authUserProvider.overrideWith(
        (ref) => Stream.error(StateError('private diagnostic')),
      ),
    ]);
    await settleUi(tester);
    expect(find.byKey(const Key('authRetry')), findsOneWidget);
    expect(find.byKey(const Key('authSignOut')), findsOneWidget);
    expect(find.textContaining('private diagnostic'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('disposing during startup cancels the minimum timer', (
    tester,
  ) async {
    await launch(tester, [
      authUserProvider.overrideWith((ref) => const Stream<User?>.empty()),
    ]);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox());
    // The test binding also checks that no timers remain at test teardown.
    expect(tester.takeException(), isNull);
  });
}
