import 'dart:io';

import 'package:fireplace/src/db/encrypted_message_store.dart';
import 'package:fireplace/src/db/history_directory_migration.dart';
import 'package:fireplace/src/db/secret_store.dart';
import 'package:fireplace/src/db/sqlite_message_store.dart';
import 'package:fireplace/src/db/ios_shared_storage.dart';
import 'package:fireplace/src/db/shared_lock.dart';

Future<Directory> accountHistoryDirectory(
  String uid,
  Directory documents,
) async {
  if (uid.isEmpty ||
      uid.contains('/') ||
      uid.contains(r'\') ||
      uid.contains('\u0000')) {
    throw StateError('Could not open message history.');
  }
  final legacy = Directory('${documents.path}/messages_$uid');
  if (!Platform.isIOS) return legacy;
  final shared = await IosSharedStorage.prepare();
  final gate = SharedLock(
    gate: CrossProcessLockGate(
      File('${shared.directory}/migration.lock'),
      isolateGate: IsolateLockGate('fireplace.preview.storage.migration'),
    ),
  );
  try {
    final destination = await migrateHistoryDirectory(
      legacy: legacy,
      destination: Directory('${shared.directory}/messages_$uid'),
      migrationLock: gate,
    );
    await IosSharedStorage.protectHistory(uid);
    return destination;
  } finally {
    await gate.close();
  }
}

/// Where the account's history database lives (decision 0057).
///
/// On Android, in the history folder. On iPhone that folder is in the
/// container shared with the notification extension, and the extension does
/// not open the database: it goes in the app's own documents instead. A
/// database held open in a shared container can get a suspended app killed
/// by iOS, and nothing but the app needs to read it.
Directory accountDatabaseDirectory(
  String uid,
  Directory documents,
  Directory historyDir,
) => Platform.isIOS ? Directory('${documents.path}/history_$uid') : historyDir;

/// Opens the account's history: the database, and behind it the per-chat
/// files from before it, each imported the first time its chat is used.
Future<SqliteMessageStore> openAccountHistory({
  required String uid,
  required Directory documents,
  required Directory historyDir,
  required SecretStore secrets,
  required SharedLock lock,
  bool createKey = true,
}) async {
  final legacy = await EncryptedFileMessageStore.open(
    dir: historyDir,
    secrets: secrets,
    uid: uid,
    lock: lock,
    createKey: createKey,
  );
  try {
    return await SqliteMessageStore.open(
      dir: accountDatabaseDirectory(uid, documents, historyDir),
      secrets: secrets,
      uid: uid,
      lock: lock,
      createKey: createKey,
      legacy: legacy,
    );
  } catch (_) {
    await legacy.close();
    rethrow;
  }
}
