import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../services/durability_test.dart' show Phone, eventually;

LocalMessage message(String id, {String? body}) => LocalMessage(
  id: id,
  chatId: 'bob_fred',
  senderUid: 'fred',
  senderDevice: 'device',
  outgoing: false,
  sentAt: DateTime.fromMillisecondsSinceEpoch(1000),
  body: body ?? id,
);

void main() {
  late Directory dir;
  late MemorySecretStore secrets;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('fp-adversarial-store-');
    secrets = MemorySecretStore();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('failed disk add must not advertise an unpersisted message', () async {
    final store = await EncryptedFileMessageStore.open(
      dir: dir,
      secrets: secrets,
      uid: 'bob',
    );
    await store.add(message('persisted'));
    final file = dir.listSync().whereType<File>().single;
    Directory('${file.path}.tmp').createSync();
    await expectLater(
      store.add(message('lost')),
      throwsA(isA<FileSystemException>()),
    );
    expect(await store.has('bob_fred', 'lost'), isFalse);
  });

  test('failed replacement preserves the previous committed body', () async {
    final store = await EncryptedFileMessageStore.open(
      dir: dir,
      secrets: secrets,
      uid: 'bob',
    );
    await store.add(message('persisted'));
    final file = dir.listSync().whereType<File>().single;
    Directory('${file.path}.tmp').createSync();
    await expectLater(
      store.add(message('persisted', body: 'replacement')),
      throwsA(isA<FileSystemException>()),
    );
    expect((await store.get('bob_fred', 'persisted'))?.body, 'persisted');
  });

  test('failed removal preserves both cached and reopened history', () async {
    final store = await EncryptedFileMessageStore.open(
      dir: dir,
      secrets: secrets,
      uid: 'bob',
    );
    await store.add(message('persisted'));
    final file = dir.listSync().whereType<File>().single;
    Directory('${file.path}.tmp').createSync();
    await expectLater(
      store.remove('bob_fred', 'persisted'),
      throwsA(isA<FileSystemException>()),
    );
    expect(await store.has('bob_fred', 'persisted'), isTrue);
    final fresh = await EncryptedFileMessageStore.open(
      dir: dir,
      secrets: secrets,
      uid: 'bob',
    );
    expect(await fresh.has('bob_fred', 'persisted'), isTrue);
  });

  test(
    'receive retry must persist history before consuming its journal',
    () async {
      final db = FakeFirebaseFirestore();
      for (final uid in ['fred', 'bob']) {
        await db.doc('usernames/$uid').set({'uid': uid});
        await db.doc('users/$uid').set({'username': uid});
      }
      final fred = await Phone.create(db, 'fred');
      final bob = await Phone.create(db, 'bob');
      final store = await EncryptedFileMessageStore.open(
        dir: dir,
        secrets: bob.secrets,
        uid: 'bob',
      );
      bob.chat = ChatService(
        db: db,
        uid: bob.uid,
        device: bob.device,
        keys: bob.keys,
        prekeys: bob.prekeys,
        secrets: bob.secrets,
        messages: store,
      );
      await fred.chat.startChat('bob');
      await bob.chat.acceptRequest('bob_fred');
      final sub = bob.chat.startSync('bob_fred');
      try {
        await fred.chat.sendText('bob_fred', 'first');
        await eventually(
          () async => (await store.watch('bob_fred').first).isNotEmpty,
          'first delivered',
        );
        final file = dir.listSync().whereType<File>().single;
        final fault = Directory('${file.path}.tmp')..createSync();
        await fred.chat.sendText('bob_fred', 'must survive');
        await eventually(
          () async =>
              bob.secrets.data.keys.any((key) => key.startsWith('journal:')),
          'receive journal retained',
        );
        // Let the first failed write finish before removing the injected disk fault.
        await Future<void>.delayed(const Duration(milliseconds: 100));
        fault.deleteSync();
        await bob.chat.retryDeferred();
        final fresh = await EncryptedFileMessageStore.open(
          dir: dir,
          secrets: bob.secrets,
          uid: 'bob',
        );
        final persisted = await fresh.watch('bob_fred').first;
        expect(
          bob.secrets.data.keys.where((key) => key.startsWith('journal:')),
          isEmpty,
        );
        expect(persisted.map((m) => m.body), contains('must survive'));
      } finally {
        await sub.cancel();
      }
    },
  );
}
