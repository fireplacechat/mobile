import 'package:flutter_test/flutter_test.dart';

import 'package:fireplace/src/db/secret_store.dart';
import 'package:fireplace/src/model/notifications/notification_preview.dart';
import 'package:fireplace/src/model/push/push_chat_index.dart';

class _CountingStore extends MemorySecretStore {
  int writes = 0;
  @override
  Future<void> write(String key, String value) {
    writes++;
    return super.write(key, value);
  }
}

void main() {
  test('finds a chat by its conversation key', () async {
    final store = MemorySecretStore();
    final index = PushChatIndex(store, 'alice');
    await index.save({'alice_bob', 'alice_carol'});
    expect(
      await index.chatFor(await conversationKey('alice_bob')),
      'alice_bob',
    );
    expect(
      await PushChatIndex(
        store,
        'alice',
      ).chatFor(await conversationKey('alice_carol')),
      'alice_carol',
    );
    expect(await index.chatFor(await conversationKey('alice_dave')), isNull);
    expect(await PushChatIndex(store, 'bob').chatFor('x'), isNull);
  });

  test('writes only when the set changes', () async {
    final store = _CountingStore();
    final index = PushChatIndex(store, 'alice');
    await index.save({'a_b', 'a_c'});
    await index.save({'a_c', 'a_b'});
    expect(store.writes, 1);
    await index.save({'a_b'});
    expect(store.writes, 2);
  });

  test('a damaged index finds nothing', () async {
    final store = MemorySecretStore()..data['pushchats:alice'] = '{not json';
    expect(await PushChatIndex(store, 'alice').chatFor('k'), isNull);
  });
}
