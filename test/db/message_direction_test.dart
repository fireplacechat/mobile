import 'package:fireplace/src/db/local_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'old linked-device history is projected without changing stored data',
    () {
      final message = LocalMessage(
        id: 'id',
        chatId: 'alice_bob',
        senderUid: 'alice',
        senderDevice: 'other-device',
        outgoing: false,
        sentAt: DateTime(2026),
        body: 'own text',
        status: MessageStatus.ok,
      );
      final before = message.toJson();
      final displayed = message.forAccount('alice');
      expect(displayed.outgoing, isTrue);
      expect(displayed.toJson(), {...before, 'outgoing': true});
      expect(message.toJson(), before);
      expect(identical(displayed.forAccount('alice'), displayed), isTrue);
      expect(identical(message.forAccount('bob'), message), isTrue);
    },
  );
}
