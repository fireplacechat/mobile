import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pending_firestore.dart';

void main() {
  for (final live in [false, true]) {
    for (final published in [false, true]) {
      test('pending local sends: live=$live, published=$published', () async {
        final db = PendingFirestore();
        final messages = db.collection('chats/alice_bob/messages');
        final secrets = MemorySecretStore();
        final keys = KeyService(FakeFirebaseFirestore(), secrets);
        final device = await keys.ensureDevice('alice');
        final history = MemoryMessageStore();
        final chat = ChatService(
          db: db,
          uid: 'alice',
          device: device,
          keys: keys,
          prekeys: PreKeyService(db, secrets),
          secrets: secrets,
          messages: history,
        );
        addTearDown(db.close);
        addTearDown(chat.close);
        await history.add(
          LocalMessage(
            id: 'pending',
            chatId: 'alice_bob',
            senderUid: 'alice',
            senderDevice: device.keys.deviceId,
            outgoing: true,
            sentAt: DateTime.utc(2026),
            body: 'not confirmed by the server',
            status: MessageStatus.unconfirmed,
          ),
        );
        final data = {
          'senderUid': 'alice',
          'senderDevice': device.keys.deviceId,
          'ts': Timestamp.fromDate(DateTime.utc(2026)),
        };
        messages.emit(
          PendingSnapshot([PendingMessage('pending', data, pending: true)]),
        );
        if (live) {
          chat.startSync('alice_bob');
          await pumpEventQueue();
        } else {
          expect(await chat.receiveOnce('alice_bob'), isFalse);
        }
        expect(
          (await history.get('alice_bob', 'pending'))!.status,
          MessageStatus.unconfirmed,
        );
        expect(
          await secrets.read('cursor:${device.keys.deviceId}:alice_bob'),
          isNull,
        );
        if (!published) {
          // A rejected write disappears from the SDK view. Its local warning
          // stays uncertain, and it must not hold up unrelated later messages.
          messages.emit(PendingSnapshot(const []));
          if (live) {
            await pumpEventQueue();
          } else {
            expect(await chat.receiveOnce('alice_bob'), isTrue);
          }
          expect(
            (await history.get('alice_bob', 'pending'))!.status,
            MessageStatus.unconfirmed,
          );
        }
        // A commit may change only metadata (the estimated timestamp already
        // matches). The listener must still receive and process that change.
        messages.emit(
          PendingSnapshot([
            PendingMessage(published ? 'pending' : 'later', data),
          ], type: DocumentChangeType.modified),
        );
        if (live) {
          expect(messages.metadataChanges, isTrue);
          await pumpEventQueue();
        } else {
          expect(await chat.receiveOnce('alice_bob'), isTrue);
        }
        expect(
          (await history.get('alice_bob', 'pending'))!.status,
          published ? MessageStatus.ok : MessageStatus.unconfirmed,
        );
        expect(
          await secrets.read('cursor:${device.keys.deviceId}:alice_bob'),
          isNotNull,
        );
      });
    }
  }
}
