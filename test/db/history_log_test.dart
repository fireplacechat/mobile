import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/db/message_mutation.dart';
import 'package:flutter_test/flutter_test.dart';

const chat = 'a_b';

LocalMessage text(String id, {String? body, String sender = 'b'}) =>
    LocalMessage(
      id: id,
      chatId: chat,
      senderUid: sender,
      senderDevice: 'device-$sender',
      outgoing: sender == 'a',
      sentAt: DateTime.fromMillisecondsSinceEpoch(1000000 + id.hashCode % 1000),
      body: body ?? 'message $id',
    );

LocalMessage control(
  String id,
  MessageMutation mutation, {
  String sender = 'b',
}) => LocalMessage(
  id: id,
  chatId: chat,
  senderUid: sender,
  senderDevice: 'device-$sender',
  outgoing: sender == 'a',
  sentAt: DateTime.fromMillisecondsSinceEpoch(2000000),
  body: '',
  mutation: mutation,
);

void main() {
  late Directory dir;
  late MemorySecretStore secrets;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('fp-history-log-');
    secrets = MemorySecretStore();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<EncryptedFileMessageStore> open() =>
      EncryptedFileMessageStore.open(dir: dir, secrets: secrets, uid: 'a');
  File snapshot() => dir.listSync().whereType<File>().singleWhere(
    (f) => f.path.endsWith('.msgs'),
  );
  File log() => File('${snapshot().path}.log');
  Future<String> shown(EncryptedFileMessageStore s) async =>
      jsonEncode([for (final m in await s.watch(chat).first) m.toJson()]);

  /// A chat just long enough to use the log.
  Future<EncryptedFileMessageStore> longChat() async {
    final s = await open();
    for (var i = 0; i < EncryptedFileMessageStore.appendFrom; i++) {
      await s.add(text('m$i'));
    }
    return s;
  }

  test(
    'a long chat appends instead of rewriting, and reopens the same',
    () async {
      final s = await longChat();
      final before = snapshot().readAsBytesSync();
      for (var i = 0; i < 5; i++) {
        await s.add(text('new$i'));
      }
      expect(snapshot().readAsBytesSync(), before, reason: 'not rewritten');
      expect(log().existsSync(), isTrue);
      final fresh = await open();
      expect(await shown(fresh), await shown(s));
      expect(await fresh.has(chat, 'new4'), isTrue);
    },
  );

  test('reactions and edits in the log survive a reopen', () async {
    final s = await longChat();
    await s.add(
      control(
        'r1',
        const MessageMutation(
          kind: MessageMutationKind.reaction,
          targetId: 'm3',
          emoji: '🔥',
          revision: 1,
          operation: ReactionOperation.set,
        ),
        sender: 'a',
      ),
    );
    await s.add(
      control(
        'e1',
        const MessageMutation(
          kind: MessageMutationKind.edit,
          targetId: 'm5',
          body: 'edited',
          revision: 1,
        ),
      ),
    );
    expect(log().existsSync(), isTrue, reason: 'appended, not rewritten');
    final fresh = await open();
    final m3 = await fresh.get(chat, 'm3');
    final m5 = await fresh.get(chat, 'm5');
    expect(m3!.reactions['a']!.emoji, '🔥');
    expect(m5!.body, 'edited');
    expect(await shown(fresh), await shown(s));
  });

  test(
    'deleting for everyone rewrites the snapshot and drops the log',
    () async {
      final s = await longChat();
      await s.add(text('secret', body: 'delete me'));
      expect(log().existsSync(), isTrue);
      await s.add(
        control(
          'd1',
          const MessageMutation(
            kind: MessageMutationKind.delete,
            targetId: 'secret',
          ),
        ),
      );
      expect(log().existsSync(), isFalse, reason: 'the deleted text is gone');
      final fresh = await open();
      expect((await fresh.get(chat, 'secret'))?.body ?? '', isEmpty);
    },
  );

  test(
    'deleting on this device rewrites the snapshot and drops the log',
    () async {
      final s = await longChat();
      await s.add(text('mine', body: 'remove me'));
      expect(log().existsSync(), isTrue);
      await s.remove(chat, 'mine');
      expect(log().existsSync(), isFalse);
      final fresh = await open();
      expect(await fresh.get(chat, 'mine'), isNull);
    },
  );

  test('the log is folded into a new snapshot when it grows', () async {
    final s = await longChat();
    final limit = EncryptedFileMessageStore.compactAfter(
      EncryptedFileMessageStore.appendFrom,
    );
    for (var i = 0; i < limit; i++) {
      await s.add(text('x$i'));
    }
    expect(log().existsSync(), isTrue);
    final before = snapshot().readAsBytesSync();
    await s.add(text('one more'));
    expect(snapshot().readAsBytesSync(), isNot(before), reason: 'folded');
    expect(log().existsSync(), isFalse);
    expect(await shown(await open()), await shown(s));
  });

  test(
    'a last entry cut short by a crash is dropped and appending goes on',
    () async {
      final s = await longChat();
      await s.add(text('kept'));
      log().writeAsBytesSync([0, 0, 1, 0, 9, 9, 9], mode: FileMode.append);
      final fresh = await open();
      expect(await fresh.has(chat, 'kept'), isTrue);
      await fresh.add(text('after'));
      final again = await open();
      expect(await again.has(chat, 'kept'), isTrue);
      expect(await again.has(chat, 'after'), isTrue);
    },
  );

  test('damage inside the log is reported, like a damaged snapshot', () async {
    final s = await longChat();
    await s.add(text('one'));
    await s.add(text('two'));
    final bytes = log().readAsBytesSync()..[40] ^= 1;
    log().writeAsBytesSync(bytes);
    final fresh = await open();
    await expectLater(fresh.has(chat, 'one'), throwsA(anything));
  });

  test('entries cannot be reordered', () async {
    final s = await longChat();
    await s.add(text('one'));
    await s.add(text('two'));
    final bytes = log().readAsBytesSync();
    final view = ByteData.sublistView(bytes);
    final first = 4 + view.getUint32(32);
    final a = bytes.sublist(32, 32 + first);
    final b = bytes.sublist(32 + first);
    log().writeAsBytesSync([...bytes.sublist(0, 32), ...b, ...a]);
    final fresh = await open();
    await expectLater(fresh.has(chat, 'one'), throwsA(anything));
  });

  test('a log left behind by an interrupted rewrite is ignored', () async {
    final s = await longChat();
    await s.add(text('gone', body: 'deleted text'));
    final leftover = log().readAsBytesSync();
    await s.remove(chat, 'gone');
    // The rewrite stopped before deleting the old log.
    log().writeAsBytesSync(leftover);
    final fresh = await open();
    expect(await fresh.get(chat, 'gone'), isNull);
    await fresh.add(text('next'));
    final again = await open();
    expect(await again.get(chat, 'gone'), isNull);
    expect(await again.has(chat, 'next'), isTrue);
  });

  test('a failed append does not advertise the message', () async {
    final s = await longChat();
    await s.add(text('first'));
    log().deleteSync();
    final fault = Directory(log().path)..createSync();
    await expectLater(s.add(text('lost')), throwsA(isA<FileSystemException>()));
    expect(await s.has(chat, 'lost'), isFalse);
    fault.deleteSync();
  });
}
