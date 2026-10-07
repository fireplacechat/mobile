import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';

typedef AppCheckActivator = Future<void> Function({
  required AndroidAppCheckProvider providerAndroid,
  required AppleAppCheckProvider providerApple,
  required bool tokenAutoRefreshEnabled,
});

/// Starts monitoring without letting an attestation failure stop startup.
Future<void> activateAppCheck({
  required bool useEmulator,
  required bool debugBuild,
  bool enabled = !const bool.fromEnvironment('APP_CHECK_OFF'),
  AppCheckActivator? activator,
}) async {
  if (useEmulator || !enabled) return;
  try {
    await (activator ?? _activate)(
      providerAndroid: debugBuild
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
      providerApple: debugBuild
          ? const AppleDebugProvider()
          : const AppleAppAttestWithDeviceCheckFallbackProvider(),
      tokenAutoRefreshEnabled: true,
    );
  } catch (_) {
    // Monitoring must not prevent access when attestation is unavailable.
  }
}

Future<void> _activate({
  required AndroidAppCheckProvider providerAndroid,
  required AppleAppCheckProvider providerApple,
  required bool tokenAutoRefreshEnabled,
}) async {
  final appCheck = FirebaseAppCheck.instance;
  await appCheck.activate(
    providerAndroid: providerAndroid,
    providerApple: providerApple,
  );
  // Set the SDK policy without waiting for refresh or requesting a token.
  unawaited(
    appCheck
        .setTokenAutoRefreshEnabled(tokenAutoRefreshEnabled)
        .catchError((Object _) {}),
  );
}
