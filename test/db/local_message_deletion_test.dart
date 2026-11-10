import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/fireplace_services.dart';

import '../support/ui_fixture.dart';

void main() {
  for (final disk in [false, true]) {
    test(
      'local deletion removes content and suppresses replay (disk=$disk)',
      () async {
        final dir = Directory.systemTemp.createTempSync('fireplace_delete');
        addTearDown(() => dir.deleteSync(recursive: true));
        final secrets = MemorySecretStore();
        final LocalMessageStore store = disk
            ? await EncryptedFileMessageStore.open(
                dir: dir,
                secrets: secrets,
                uid: 'alice',
              )
            : MemoryMessageStore();
        final original = message(id: 'delete', body: 'private fictional text');
        await store.add(original);
        await store.remove(original.chatId, original.id);
        await store.add(original);
        expect(await store.get(original.chatId, original.id), isNull);
        expect(await store.has(original.chatId, original.id), isTrue);
        expect(await store.watch(original.chatId).first, isEmpty);
        await store.remove(original.chatId, 'memory-only');
        expect(await store.has(original.chatId, 'memory-only'), isTrue);
        if (disk) {
          await (store as EncryptedFileMessageStore).close();
          final reopened = await EncryptedFileMessageStore.open(
            dir: dir,
            secrets: secrets,
            uid: 'alice',
          );
          await reopened.add(original);
          expect(await reopened.watch(original.chatId).first, isEmpty);
          expect(await reopened.get(original.chatId, original.id), isNull);
          await reopened.close();
        }
      },
    );
  }
}
