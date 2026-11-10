import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/db/message_quote.dart';

import '../support/ui_fixture.dart';

void main() {
  test('quote validation is bounded and old records still load', () {
    expect(
      LocalMessage.fromJson(message(id: 'a', body: 'Old text').toJson()).quote,
      isNull,
    );
    for (final data in [
      {'targetId': '../a', 'senderUid': 'fred', 'body': 'text'},
      {'targetId': 'a', 'senderUid': '', 'body': 'text'},
      {'targetId': 'a', 'senderUid': 'fred', 'body': 'x' * 1025},
    ]) {
      expect(() => MessageQuote.fromJson(data), throwsFormatException);
    }
  });
  test(
    'encrypted reload preserves quote; deleting original scrubs its copies',
    () async {
      final dir = Directory.systemTemp.createTempSync('fireplace_quote');
      addTearDown(() => dir.deleteSync(recursive: true));
      final secrets = MemorySecretStore();
      var store = await EncryptedFileMessageStore.open(
        dir: dir,
        secrets: secrets,
        uid: 'alice',
      );
      final original = message(id: 'original', body: 'Fictional secret');
      final reply = message(id: 'reply', body: 'Response').copyWith(
        quote: MessageQuote(
          targetId: original.id,
          senderUid: original.senderUid,
          body: original.body,
        ),
      );
      await store.add(reply);
      await store.add(original);
      await store.close();
      store = await EncryptedFileMessageStore.open(
        dir: dir,
        secrets: secrets,
        uid: 'alice',
      );
      expect(
        (await store.get(reply.chatId, reply.id))!.quote!.body,
        original.body,
      );
      await store.remove(original.chatId, original.id);
      await store.add(reply);
      expect(
        (await store.get(reply.chatId, reply.id))!.quote!.unavailable,
        isTrue,
      );
      expect((await store.get(reply.chatId, reply.id))!.quote!.body, isEmpty);
      await store.close();
    },
  );
}
