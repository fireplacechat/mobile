import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'package:fireplace/firebase_options.dart';
import 'package:fireplace/src/app/app_check.dart';

/// Firebase, App Check and, in emulator builds, the emulators: the same in
/// the app and in the background push handler's isolate.
///
/// Run against local emulators with:
///   flutter run --dart-define=USE_EMULATOR=true   (Android emulator uses 10.0.2.2)
Future<void> setUpFirebase() async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await activateAppCheck(
    useEmulator: const bool.fromEnvironment('USE_EMULATOR'),
    debugBuild: kDebugMode,
  );
  if (const bool.fromEnvironment('USE_EMULATOR')) {
    const host = String.fromEnvironment(
      'EMULATOR_HOST',
      defaultValue: '10.0.2.2',
    );
    // On Windows a system service can hold 8080; then run the emulator on
    // another port and pass it as EMULATOR_FIRESTORE_PORT.
    const firestorePort = int.fromEnvironment(
      'EMULATOR_FIRESTORE_PORT',
      defaultValue: 8080,
    );
    await FirebaseAuth.instance.useAuthEmulator(host, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(host, firestorePort);
  }
}
