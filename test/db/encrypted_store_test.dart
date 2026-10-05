import 'dart:io';

import 'package:fireplace/fireplace_services.dart';
import 'package:flutter_test/flutter_test.dart';

LocalMessage msg(String id, String body, int t) => LocalMessage(
  id: id,
  chatId: 'a_b',
  senderUid: 'a',
  senderDevice: 'd',
  outgoing: true,
  sentAt: DateTime.fromMillisecondsSinceEpoch(t),
  body: body,
);

void main() {
  late Directory dir;
  late MemorySecretStore secrets;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('fp_store');
    secrets = MemorySecretStore();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test(
    'persists across reopen, ordered, and files hold no plaintext',
    () async {
      var s = await EncryptedFileMessageStore.open(
        dir: dir,
        secrets: secrets,
        uid: 'a',
      );
      await s.add(msg('2', 'second top-secret-phrase', 2000));
      await s.add(msg('1', 'first', 1000));
      expect(await s.has('a_b', '1'), isTrue);
      for (final f in dir.listSync().whereType<File>()) {
        expect(
          String.fromCharCodes(f.readAsBytesSync()).contains('top-secret'),
          isFalse,
        );
      }
      s = await EncryptedFileMessageStore.open(
        dir: dir,
        secrets: secrets,
        uid: 'a',
      );
      final list = await s.watch('a_b').first;
      expect(list.map((m) => m.body), ['first', 'second top-secret-phrase']);
    },
  );

  test('watch emits on add; wrong key cannot read; tamper detected', () async {
    final s = await EncryptedFileMessageStore.open(
      dir: dir,
      secrets: secrets,
      uid: 'a',
    );
    final seen = <int>[];
    final sub = s.watch('a_b').listen((l) => seen.add(l.length));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await s.add(msg('1', 'x', 1));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();
    expect(seen, [0, 1]);

    final other = await EncryptedFileMessageStore.open(
      dir: dir,
      secrets: MemorySecretStore(),
      uid: 'a',
    );
    await expectLater(other.has('a_b', '1'), throwsA(anything));

    final f = dir.listSync().whereType<File>().firstWhere(
      (f) => f.path.endsWith('.msgs'),
    );
    final bytes = f.readAsBytesSync()..[20] ^= 1;
    f.writeAsBytesSync(bytes);
    final fresh = await EncryptedFileMessageStore.open(
      dir: dir,
      secrets: secrets,
      uid: 'a',
    );
    await expectLater(fresh.has('a_b', '1'), throwsA(anything));
  });
}
