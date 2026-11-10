import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/db/message_mutation.dart';

LocalMessage textMessage() => LocalMessage(
  id: 'text',
  chatId: 'alice_bob',
  senderUid: 'alice',
  senderDevice: 'a',
  outgoing: false,
  sentAt: DateTime.utc(2026),
  body: 'fictional secret',
);

LocalMessage control(
  String id, {
  String actor = 'bob',
  int revision = 1,
  String emoji = '❤️',
  ReactionOperation operation = ReactionOperation.set,
  MessageMutationKind kind = MessageMutationKind.reaction,
  MessageStatus status = MessageStatus.ok,
}) => LocalMessage(
  id: id,
  chatId: 'alice_bob',
  senderUid: actor,
  senderDevice: actor,
  outgoing: false,
  sentAt: DateTime.utc(2026),
  body: '',
  status: status,
  mutation: MessageMutation(
    kind: kind,
    targetId: 'text',
    emoji: emoji,
    operation: operation,
    revision: revision,
  ),
);

void main() {
  test('validates bounded emoji sequences and strict control fields', () {
    for (final emoji in ['❤️', '👍🏽', '😂', '👩‍💻', '🇬🇧', '1️⃣']) {
      expect(validReactionEmoji(emoji), isTrue, reason: emoji);
    }
    for (final emoji in ['', 'hello', '👍👍', 'a' * 65, '\n', '🇬']) {
      expect(validReactionEmoji(emoji), isFalse, reason: emoji);
    }
    final valid = control('event').mutation!.toJson();
    expect(MessageMutation.fromJson(valid).emoji, '❤️');
    for (final patch in [
      {'revision': 0},
      {'revision': 1.5},
      {'revision': 9007199254740992},
      {'targetId': '../text'},
      {'emoji': 'text'},
      {'operation': 'toggle'},
    ]) {
      expect(
        () => MessageMutation.fromJson({...valid, ...patch}),
        throwsA(anything),
      );
    }
  });

  test(
    'random order, duplicates and clears converge for both actors',
    () async {
      final records = [
        textMessage(),
        control('b1'),
        control('b2', revision: 2, emoji: '😂'),
        control(
          'b3',
          revision: 3,
          emoji: '😂',
          operation: ReactionOperation.clear,
        ),
        control('a1', actor: 'alice', emoji: '👍'),
      ];
      for (var seed = 0; seed < 30; seed++) {
        final store = MemoryMessageStore();
        for (final record in ([
          ...records,
          ...records,
        ]..shuffle(Random(seed)))) {
          await store.add(record);
        }
        final history = await store.watch('alice_bob').first;
        expect(history, hasLength(1));
        expect(history.single.reactions['bob']!.emoji, isNull);
        expect(history.single.reactions['bob']!.revision, 3);
        expect(history.single.reactions['alice']!.emoji, '👍');
      }
    },
  );

  test(
    'delete author, missing target, body erasure and replay across reopen',
    () async {
      final dir = Directory.systemTemp.createTempSync('fireplace_controls');
      addTearDown(() => dir.deleteSync(recursive: true));
      final secrets = MemorySecretStore();
      var store = await EncryptedFileMessageStore.open(
        dir: dir,
        secrets: secrets,
        uid: 'bob',
      );
      await store.add(control('bad-delete', kind: MessageMutationKind.delete));
      await store.add(textMessage());
      expect((await store.get('alice_bob', 'text'))!.body, 'fictional secret');
      await store.add(control('reaction'));
      await store.add(
        control('delete', actor: 'alice', kind: MessageMutationKind.delete),
      );
      expect((await store.get('alice_bob', 'text'))!.body, isEmpty);
      expect((await store.get('alice_bob', 'text'))!.reactions, isEmpty);
      expect(await store.get('alice_bob', 'reaction'), isNull);
      await store.close();
      store = await EncryptedFileMessageStore.open(
        dir: dir,
        secrets: secrets,
        uid: 'bob',
      );
      await store.add(textMessage());
      expect((await store.get('alice_bob', 'text'))!.remotelyDeleted, isTrue);
      expect((await store.get('alice_bob', 'text'))!.body, isEmpty);
      await store.remove('alice_bob', 'text');
      await store.add(control('later', revision: 7));
      expect(await store.watch('alice_bob').first, isEmpty);
      await store.close();
    },
  );

  test(
    'unconfirmed control stays hidden and applies only when confirmed',
    () async {
      final store = MemoryMessageStore();
      await store.add(textMessage());
      final pending = control('pending', status: MessageStatus.unconfirmed);
      await store.add(pending);
      expect((await store.watch('alice_bob').first).single.reactions, isEmpty);
      await store.add(pending.copyWith(status: MessageStatus.ok));
      expect(
        (await store.watch('alice_bob').first).single.reactions['bob']!.emoji,
        '❤️',
      );
    },
  );
}
