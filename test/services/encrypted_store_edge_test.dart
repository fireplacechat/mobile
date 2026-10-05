import 'dart:io';

import 'package:fireplace/fireplace_services.dart';
import 'package:flutter_test/flutter_test.dart';

LocalMessage message(String id, int time) => LocalMessage(
  id: id,
  chatId: 'alice_bob',
  senderUid: 'alice',
  senderDevice: 'device_a',
  outgoing: true,
  sentAt: DateTime.fromMillisecondsSinceEpoch(time),
  body: 'body-$id',
);

void main() {
  late Directory dir;
  late MemorySecretStore secrets;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('fireplace-store-edge-');
    secrets = MemorySecretStore();
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test(
    'many concurrent adds persist once and remain sorted after reopen',
    () async {
      final store = await EncryptedFileMessageStore.open(
        dir: dir,
        secrets: secrets,
        uid: 'alice',
      );

      await Future.wait([
        for (var i = 39; i >= 0; i--) store.add(message('$i', i)),
      ]);

      final reopened = await EncryptedFileMessageStore.open(
        dir: dir,
        secrets: secrets,
        uid: 'alice',
      );
      final history = await reopened.watch('alice_bob').first;
      expect(history, hasLength(40));
      expect(history.map((m) => m.id), [for (var i = 0; i < 40; i++) '$i']);
      expect(await reopened.has('alice_bob', '17'), isTrue);
    },
  );

  test(
    'corrupt encrypted file is reported and never returned as history',
    () async {
      final store = await EncryptedFileMessageStore.open(
        dir: dir,
        secrets: secrets,
        uid: 'alice',
      );
      await store.add(message('1', 1));
      final file = dir.listSync().whereType<File>().single;
      final bytes = await file.readAsBytes();
      await file.writeAsBytes(bytes.sublist(0, bytes.length - 1));

      final reopened = await EncryptedFileMessageStore.open(
        dir: dir,
        secrets: secrets,
        uid: 'alice',
      );
      await expectLater(reopened.has('alice_bob', '1'), throwsA(anything));
    },
  );
}
