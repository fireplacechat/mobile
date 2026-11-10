import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/db/message_mutation.dart';

import '../support/ui_fixture.dart';

LocalMessage revision(
  int number, {
  String actor = 'fred',
  String device = 'a',
  MessageStatus status = MessageStatus.ok,
}) => LocalMessage(
  id: 'edit-$number-$actor-$device',
  chatId: 'alice_fred',
  senderUid: actor,
  senderDevice: device,
  outgoing: actor == 'alice',
  sentAt: fixtureTime.add(Duration(minutes: number)),
  body: '',
  status: status,
  mutation: MessageMutation(
    kind: MessageMutationKind.edit,
    targetId: 'original',
    body: 'Version $number $device',
    revision: number,
  ),
);

void main() {
  test('bounded revisions reject malformed edits', () {
    for (final body in ['', ' ', 'a' * 16385]) {
      expect(
        () => MessageMutation.fromJson({
          'type': 'edit',
          'targetId': 'a',
          'body': body,
          'revision': 1,
        }),
        throwsFormatException,
      );
    }
    for (final number in [0, 11, '1']) {
      expect(
        () => MessageMutation.fromJson({
          'type': 'edit',
          'targetId': 'a',
          'body': 'Text',
          'revision': number,
        }),
        throwsFormatException,
      );
    }
  });
  test(
    'unknown targets, random order, duplicates and linked ties converge',
    () async {
      for (var seed = 0; seed < 30; seed++) {
        final store = MemoryMessageStore();
        final events = [
          message(id: 'original', body: 'Original'),
          revision(1),
          revision(2),
          revision(2, device: 'z'),
          revision(3, actor: 'alice'),
        ];
        events.shuffle(Random(seed));
        for (final event in events) {
          await store.add(event);
        }
        await store.add(revision(1));
        final result = (await store.watch('alice_fred').first).single;
        expect(result.body, 'Version 2 z');
        expect(result.originalBody, 'Original');
        expect(result.edits.keys.toSet(), {1, 2});
        expect(result.editClock, 2);
      }
    },
  );
  test(
    'unconfirmed edits reserve a revision but never change visible text',
    () async {
      final store = MemoryMessageStore();
      await store.add(message(id: 'original', body: 'Original'));
      await store.add(revision(1, status: MessageStatus.unconfirmed));
      var result = (await store.watch('alice_fred').first).single;
      expect(result.body, 'Original');
      expect(result.editClock, 1);
      expect(result.edits, isEmpty);
      await store.add(revision(1));
      result = (await store.watch('alice_fred').first).single;
      expect(result.edits.length, 1);
    },
  );
  test(
    'encrypted reopen keeps history; remote and local deletion erase it',
    () async {
      final dir = Directory.systemTemp.createTempSync('fireplace_edits');
      addTearDown(() => dir.deleteSync(recursive: true));
      final secrets = MemorySecretStore();
      var store = await EncryptedFileMessageStore.open(
        dir: dir,
        secrets: secrets,
        uid: 'alice',
      );
      await store.add(message(id: 'original', body: 'Original'));
      await store.add(revision(1));
      await store.close();
      store = await EncryptedFileMessageStore.open(
        dir: dir,
        secrets: secrets,
        uid: 'alice',
      );
      expect((await store.watch('alice_fred').first).single.edits.length, 1);
      await store.add(
        LocalMessage(
          id: 'delete',
          chatId: 'alice_fred',
          senderUid: 'fred',
          senderDevice: 'a',
          outgoing: false,
          sentAt: fixtureTime,
          body: '',
          mutation: const MessageMutation(
            kind: MessageMutationKind.delete,
            targetId: 'original',
          ),
        ),
      );
      await store.add(revision(2));
      final result = (await store.watch('alice_fred').first).single;
      expect(result.body, isEmpty);
      expect(result.originalBody, isEmpty);
      expect(result.edits, isEmpty);
      expect(await store.get('alice_fred', revision(1).id), isNull);
      await store.remove('alice_fred', 'original');
      await store.add(revision(3));
      expect(await store.watch('alice_fred').first, isEmpty);
      await store.close();
    },
  );
}
