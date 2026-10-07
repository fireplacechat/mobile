import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:fireplace/src/app/app_check.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('emulators skip App Check before calling the activator', () async {
    final fake = _FakeActivator();
    await activateAppCheck(
      useEmulator: true,
      debugBuild: false,
      activator: fake.call,
    );
    expect(fake.calls, 0);
  });

  test('disabled App Check never calls the activator', () async {
    final fake = _FakeActivator();
    await activateAppCheck(
      useEmulator: false,
      debugBuild: true,
      enabled: false,
      activator: fake.call,
    );
    expect(fake.calls, 0);
  });

  test(
    'debug builds select both debug providers and automatic refresh',
    () async {
      final fake = _FakeActivator();
      await activateAppCheck(
        useEmulator: false,
        debugBuild: true,
        activator: fake.call,
      );
      expect(fake.calls, 1);
      expect(fake.android, isA<AndroidDebugProvider>());
      expect(fake.apple, isA<AppleDebugProvider>());
      expect(fake.refresh, isTrue);
    },
  );

  test(
    'release builds select Play Integrity and App Attest fallback',
    () async {
      final fake = _FakeActivator();
      await activateAppCheck(
        useEmulator: false,
        debugBuild: false,
        activator: fake.call,
      );
      expect(fake.calls, 1);
      expect(fake.android, isA<AndroidPlayIntegrityProvider>());
      expect(fake.apple, isA<AppleAppAttestWithDeviceCheckFallbackProvider>());
      expect(fake.refresh, isTrue);
    },
  );

  test('asynchronous activation failure does not stop startup', () async {
    final fake = _FakeActivator()..failure = StateError('unavailable');
    await expectLater(
      activateAppCheck(
        useEmulator: false,
        debugBuild: false,
        activator: fake.call,
      ),
      completes,
    );
    expect(fake.calls, 1);
  });

  test('synchronous activation failure does not stop startup', () async {
    await expectLater(
      activateAppCheck(
        useEmulator: false,
        debugBuild: false,
        activator: ({
          required providerAndroid,
          required providerApple,
          required tokenAutoRefreshEnabled,
        }) => throw StateError('unavailable'),
      ),
      completes,
    );
  });

  test('startup awaits provider activation', () async {
    final gate = Completer<void>();
    final fake = _FakeActivator()..gate = gate;
    var completed = false;
    final startup = activateAppCheck(
      useEmulator: false,
      debugBuild: false,
      activator: fake.call,
    ).then((_) => completed = true);
    await Future<void>.delayed(Duration.zero);
    expect(fake.calls, 1);
    expect(completed, isFalse);
    gate.complete();
    await startup;
    expect(completed, isTrue);
  });
}

class _FakeActivator {
  int calls = 0;
  AndroidAppCheckProvider? android;
  AppleAppCheckProvider? apple;
  bool? refresh;
  Object? failure;
  Completer<void>? gate;

  Future<void> call({
    required AndroidAppCheckProvider providerAndroid,
    required AppleAppCheckProvider providerApple,
    required bool tokenAutoRefreshEnabled,
  }) async {
    calls++;
    android = providerAndroid;
    apple = providerApple;
    refresh = tokenAutoRefreshEnabled;
    if (failure case final failure?) throw failure;
    await gate?.future;
  }
}
