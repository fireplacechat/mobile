import 'dart:io';

import 'package:fireplace/src/db/shared_lock.dart';

/// Move ciphertext and sidecars together without decrypting or rewriting them.
/// A rename is atomic; an interruption leaves the complete directory at one
/// location. Conflicting directories are preserved for recovery, never merged.
Future<Directory> migrateHistoryDirectory({
  required Directory legacy,
  required Directory destination,
  required SharedLock migrationLock,
}) => migrationLock.run(() async {
  final sourceExists = await legacy.exists();
  final targetExists = await destination.exists();
  if (sourceExists && targetExists) {
    throw StateError('Message history needs attention.');
  }
  if (sourceExists) {
    await destination.parent.create(recursive: true);
    return legacy.rename(destination.path);
  }
  if (!targetExists) await destination.create(recursive: true);
  return destination;
});
