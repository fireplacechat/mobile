import 'dart:io';

import 'package:fireplace/src/db/history_directory_migration.dart';
import 'package:fireplace/src/db/shared_lock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root, legacy, destination;
  late SharedLock lock;
  setUp(() async {
    root = await Directory.systemTemp.createTemp(
      'fireplace-history-migration-',
    );
    legacy = Directory('${root.path}/documents/messages_fictional');
    destination = Directory('${root.path}/group/messages_fictional');
    lock = SharedLock();
  });
  tearDown(() async {
    await lock.close();
    await root.delete(recursive: true);
  });
  Future<Directory> migrate() => migrateHistoryDirectory(
    legacy: legacy,
    destination: destination,
    migrationLock: lock,
  );

  test(
    'moves all ciphertext and sidecars unchanged and can repeat after restart',
    () async {
      await legacy.create(recursive: true);
      final fixtures = {
        'fictional.msgs': [0, 255, 1, 2],
        'fictional.msgs.log': [3, 4, 5],
        'chat-ui.enc': [6, 7, 8],
      };
      for (final entry in fixtures.entries) {
        await File('${legacy.path}/${entry.key}').writeAsBytes(entry.value);
      }
      await Future.wait([migrate(), migrate()]);
      expect(await legacy.exists(), isFalse);
      for (final entry in fixtures.entries) {
        expect(
          await File('${destination.path}/${entry.key}').readAsBytes(),
          entry.value,
        );
      }
      expect((await migrate()).path, destination.path);
    },
  );

  test(
    'conflicting directories preserve both copies and refuse to open',
    () async {
      await legacy.create(recursive: true);
      await destination.create(recursive: true);
      await File('${legacy.path}/fictional.msgs').writeAsBytes([1]);
      await File('${destination.path}/fictional.msgs').writeAsBytes([2]);
      await expectLater(migrate(), throwsStateError);
      expect(await File('${legacy.path}/fictional.msgs').readAsBytes(), [1]);
      expect(await File('${destination.path}/fictional.msgs').readAsBytes(), [
        2,
      ]);
    },
  );

  test('a new install creates only its shared directory', () async {
    await migrate();
    expect(await destination.exists(), isTrue);
    expect(await legacy.exists(), isFalse);
  });
}
