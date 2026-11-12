import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app.dart';
import 'package:fireplace/src/app/background_push_entry.dart';
import 'package:fireplace/src/app/firebase_setup.dart';
import 'package:fireplace/src/model/push/push_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setUpFirebase();
  // Android posts its own notifications from a background isolate, after
  // decrypting the push on the phone (decision 0030).
  if (pushEnabled && Platform.isAndroid) {
    FirebaseMessaging.onBackgroundMessage(fireplaceBackgroundMessage);
  }
  runApp(
    // Session errors (needs recovery, account deletion pending, offline) are
    // states to show, not something to retry silently in the background.
    ProviderScope(retry: (_, _) => null, child: const FireplaceApp()),
  );
}
