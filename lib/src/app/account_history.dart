import 'dart:io';

import 'package:fireplace/src/db/history_directory_migration.dart';
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
