// Search reads the history database (decision 0057, step 4): the database
// finds the newest matches on its own connection and isolate, with the same
// matching as before, and reads nothing else.
import 'dart:io';

import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/db/message_mutation.dart';
import 'package:fireplace/src/db/sqlite_message_store.dart';
import 'package:fireplace/src/model/search/message_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late MemorySecretStore secrets;
  final opened = <SqliteMessageStore>[];
  setUp(() {
    dir = Directory.systemTemp.createTempSync('fp_search');
    secrets = MemorySecretStore();
  });
  tearDown(() async {
    for (final store in opened) {
      await store.close();
    }
    opened.clear();
    dir.deleteSync(recursive: true);
  });

  Future<SqliteMessageStore> open({EncryptedFileMessageStore? legacy}) async {
    final store = await SqliteMessageStore.open(
      dir: dir,
      secrets: secrets,
      uid: 'alice',
      legacy: legacy,
    );
    opened.add(store);
    return store;
  }

  final base = DateTime.utc(2026, 11, 1);
  LocalMessage message(
    String chat,
    String id,
    String body, {
    int minute = 0,
    MessageStatus status = MessageStatus.ok,
    MessageMutation? mutation,
  }) => LocalMessage(
    id: id,
    chatId: chat,
    senderUid: 'bob',
    senderDevice: 'd',
    outgoing: false,
    sentAt: base.add(Duration(minutes: minute)),
    body: body,
    status: status,
    mutation: mutation,
  );

  List<String> ids(List<LocalMessage> found) => [for (final m in found) m.id];

  test('the newest readable matches, across the chats asked for', () async {
    final store = await open();
    await store.add(message('a', 'old', 'lunch on friday', minute: 1));
    await store.add(message('b', 'new', 'Lunch again?', minute: 9));
    await store.add(message('a', 'mid', 'about lunch', minute: 5));
    await store.add(message('c', 'elsewhere', 'lunch in c', minute: 7));
    await store.add(message('a', 'other', 'nothing here', minute: 6));
    await store.add(
      message('a', 'unreadable', 'lunch', status: MessageStatus.undecryptable),
    );
    await store.add(
      message('a', 'notice', 'lunch', status: MessageStatus.notice),
    );
    final matches = messageMatcher('LUNCH');
    expect(ids(await store.search({'a', 'b'}, matches)), ['new', 'mid', 'old']);
    expect(ids(await store.search({'a', 'b'}, matches, limit: 2)), [
      'new',
      'mid',
    ]);
    expect(await store.search(const {}, matches), isEmpty);
  });

  test(
    'an edit is found by its new text, a deleted message not at all',
    () async {
      final store = await open();
      await store.add(message('a', 'm1', 'see you at noon'));
      await store.add(
        message(
          'a',
          'e1',
          '',
          minute: 1,
          mutation: const MessageMutation(
            kind: MessageMutationKind.edit,
            targetId: 'm1',
            body: 'see you at two',
            revision: 1,
          ),
        ),
      );
      await store.add(message('a', 'm2', 'two coffees', minute: 2));
      await store.add(
        message(
          'a',
          'd2',
          '',
          minute: 3,
          mutation: const MessageMutation(
            kind: MessageMutationKind.delete,
            targetId: 'm2',
          ),
        ),
      );
      await store.add(message('a', 'm3', 'two more', minute: 4));
      await store.remove('a', 'm3');
      expect(ids(await store.search({'a'}, messageMatcher('two'))), ['m1']);
      expect(await store.search({'a'}, messageMatcher('noon')), isEmpty);
    },
  );

  test(
    'matching is the same as before: formatting, case and accents',
    () async {
      final store = await open();
      final bodies = {
        'bold': '**Saturday** sounds good',
        'sigma': 'ΟΔΟΣ',
        'accent': 'café crème',
        'emoji': 'tea ☕ at four',
      };
      var minute = 0;
      for (final e in bodies.entries) {
        await store.add(message('a', e.key, e.value, minute: minute++));
      }
      for (final query in ['saturday', '**', 'οδος', 'CAFÉ', 'cafe', '☕ at']) {
        final before = searchMessages({
          'a': [for (final e in bodies.entries) message('a', e.key, e.value)],
        }, query).map((h) => h.message.id).toSet();
        final now = ids(await store.search({'a'}, messageMatcher(query)))
            .toSet();
        expect(now, before, reason: query);
      }
    },
  );

  test(
    'a chat still in its file from before the database is searched',
    () async {
      final files = await EncryptedFileMessageStore.open(
        dir: dir,
        secrets: secrets,
        uid: 'alice',
      );
      await files.add(message('a', 'filed', 'from the old file'));
      await files.close();
      final store = await open(
        legacy: await EncryptedFileMessageStore.open(
          dir: dir,
          secrets: secrets,
          uid: 'alice',
        ),
      );
      expect(ids(await store.search({'a'}, messageMatcher('old file'))), [
        'filed',
      ]);
    },
  );
}
