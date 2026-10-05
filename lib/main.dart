import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/firebase_options.dart';
import 'package:fireplace/src/app.dart';

/// Run against local emulators with:
///   flutter run --dart-define=USE_EMULATOR=true   (Android emulator uses 10.0.2.2)
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (const bool.fromEnvironment('USE_EMULATOR')) {
    const host = String.fromEnvironment(
      'EMULATOR_HOST',
      defaultValue: '10.0.2.2',
    );
    await FirebaseAuth.instance.useAuthEmulator(host, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
  }
  runApp(
    // Session errors (needs recovery, account deletion pending, offline) are
    // states to show, not something to retry silently in the background.
    ProviderScope(retry: (_, _) => null, child: const FireplaceApp()),
  );
}
