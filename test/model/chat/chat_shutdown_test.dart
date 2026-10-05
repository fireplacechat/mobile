import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:flutter_test/flutter_test.dart';

class PausedHistory extends MemoryMessageStore {
  final entered = Completer<void>();
  final release = Completer<void>();
  bool paused = false;
  @override
  Future<bool> has(String chatId, String messageId) async {
    if (!paused) {
      paused = true;
      entered.complete();
      await release.future;
    }
    return super.has(chatId, messageId);
  }
}

void main() {
  test('chat shutdown drains a receive and stops later sync work', () async {
    final db = FakeFirebaseFirestore();
    Future<ChatService> make(String uid, LocalMessageStore messages) async {
      await db.doc('users/$uid').set({'username': uid});
      await db.doc('usernames/$uid').set({'uid': uid});
      final secrets = MemorySecretStore();
      final keys = KeyService(db, secrets);
      final device = await keys.ensureDevice(uid);
      final prekeys = PreKeyService(db, secrets);
      await prekeys.maintain(uid, device);
      return ChatService(
        db: db,
        uid: uid,
        device: device,
        keys: keys,
        prekeys: prekeys,
        secrets: secrets,
        messages: messages,
      );
    }

    final history = PausedHistory();
    final fred = await make('fred', MemoryMessageStore());
    final bob = await make('bob', history);
    final chatId = await fred.startChat('bob');
    bob.startSync(chatId);
    await fred.sendText(chatId, 'Hello');
    await history.entered.future.timeout(const Duration(seconds: 5));
    var finished = false;
    final closing = bob.close().then((_) {
      finished = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(finished, isFalse);
    history.release.complete();
    await closing.timeout(const Duration(seconds: 5));
    await bob.close();
    final initial = await history.watch(chatId).first;
    expect(initial, hasLength(1));
    await fred.sendText(chatId, 'Later');
    await bob.retryDeferred();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(await history.watch(chatId).first, hasLength(1));
    expect(() => bob.startSync(chatId), throwsStateError);
    await fred.close();
  });
}
