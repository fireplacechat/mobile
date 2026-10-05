import 'dart:async';
import 'dart:io';

import 'package:fireplace/fireplace_services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late MemorySecretStore secrets;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('fp-history-stream');
    secrets = MemorySecretStore();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<EncryptedFileMessageStore> corruptStore() async {
    final store = await EncryptedFileMessageStore.open(
      dir: dir,
      secrets: secrets,
      uid: 'fred',
    );
    await store.add(
      LocalMessage(
        id: 'one',
        chatId: 'fred_bob',
        senderUid: 'bob',
        senderDevice: 'device',
        outgoing: false,
        sentAt: DateTime(2026),
        body: 'Hello',
      ),
    );
    final file = dir.listSync().whereType<File>().single;
    final bytes = file.readAsBytesSync();
    bytes[bytes.length - 1] ^= 1;
    file.writeAsBytesSync(bytes);
    return EncryptedFileMessageStore.open(
      dir: dir,
      secrets: secrets,
      uid: 'fred',
    );
  }

  test('history first reports a load error', () async {
    final store = await corruptStore();
    await expectLater(
      store.watch('fred_bob').first.timeout(const Duration(seconds: 2)),
      throwsA(isNot(isA<TimeoutException>())),
    );
  });

  test('history listener receives a load error', () async {
    final store = await corruptStore();
    final error = Completer<Object>();
    final sub = store
        .watch('fred_bob')
        .listen(
          (_) => fail('Unexpected history'),
          onError: (Object e) => error.complete(e),
        );
    try {
      expect(await error.future.timeout(const Duration(seconds: 2)), isNotNull);
    } finally {
      await sub.cancel();
    }
  });

  test('cancelled history load emits neither data nor error', () async {
    final store = await corruptStore();
    final events = <Object>[];
    final sub = store.watch('fred_bob').listen(events.add, onError: events.add);
    await sub.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(events, isEmpty);
  });
}
