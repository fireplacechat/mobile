import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:path_provider/path_provider.dart';

import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/app/firebase_setup.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/notifications/preview_notifier.dart';
import 'package:fireplace/src/model/push/background_push.dart';
import 'package:fireplace/src/model/safety/push_challenge.dart';

/// The background push handler (Android, decision 0030). firebase_messaging
/// runs it in its own isolate whenever a data push arrives and Fireplace is
/// not on screen, whether or not the app's own isolate is alive.
@pragma('vm:entry-point')
Future<void> fireplaceBackgroundMessage(RemoteMessage message) async {
  try {
    await setUpFirebase();
  } catch (_) {
    // Already set up in this isolate (a second push), or no network yet.
  }
  final data = {for (final e in message.data.entries) e.key: '${e.value}'};
  final uid = await _signedInUid();
  final db = FirebaseFirestore.instance;
  if (data['type'] == 'rateLimitChallenge') {
    if (uid != null) await PushChallenge(db).answer(data, uid);
    return;
  }
  await BackgroundPush(
    uid: uid,
    prefs: SecureSecretStore(),
    notifier: _notifier,
    open: (uid) => _open(db, uid),
  ).handle(data);
}

// Kept for the life of the isolate.
final _notifier = PreviewNotifier(const NativeNotificationPoster());

Future<String?> _signedInUid() async {
  final auth = FirebaseAuth.instance;
  if (auth.currentUser != null) return auth.currentUser!.uid;
  try {
    // The saved session is restored shortly after start-up.
    final user = await auth.authStateChanges().first.timeout(
      const Duration(seconds: 2),
    );
    return user?.uid;
  } catch (_) {
    return null;
  }
}

/// This account's stores, as the app opens them but never creating anything:
/// no device, no history key.
Future<BackgroundSession> _open(FirebaseFirestore db, String uid) async {
  final secrets = SecureSecretStore();
  final keys = KeyService(db, secrets);
  final device = await keys.existingDevice(uid);
  if (device == null) throw StateError('Not set up on this device.');
  final docs = await getApplicationDocumentsDirectory();
  final historyDir = Directory('${docs.path}/messages_$uid');
  if (!await historyDir.exists()) throw StateError('No history yet.');
  final lock = accountLock(uid, historyDir);
  try {
    final store = await EncryptedFileMessageStore.open(
      dir: historyDir,
      secrets: secrets,
      uid: uid,
      lock: lock,
      createKey: false,
    );
    final chat = ChatService(
      db: db,
      uid: uid,
      device: device,
      keys: keys,
      prekeys: PreKeyService(db, secrets, lock: lock),
      secrets: secrets,
      messages: store,
      lock: lock,
    );
    return BackgroundSession(
      chat: chat,
      store: store,
      close: () async {
        await chat.close();
        await store.close();
        await lock.close();
      },
    );
  } catch (_) {
    await lock.close();
    rethrow;
  }
}
