import 'dart:async';
import 'dart:io';

import 'package:fireplace/src/model/settings/local_chat_preferences.dart';
import 'package:fireplace/src/db/secret_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'preferences encrypted at rest, reopen preserves IDs, mute and preview',
    () async {
      final dir = await Directory.systemTemp.createTemp('fireplace-prefs-');
      addTearDown(() => dir.delete(recursive: true));
      final secrets = MemorySecretStore();
      final p = await LocalChatPreferences.open(
        dir: dir,
        secrets: secrets,
        uid: 'alice',
      );
      await p.markSeen('chat-sensitive-name', ['message-id-sensitive']);
      await p.mute('chat-sensitive-name', true);
      await p.previews(true);
      final bytes = await File('${dir.path}/chat-ui.enc').readAsBytes();
      expect(
        String.fromCharCodes(bytes),
        isNot(contains('chat-sensitive-name')),
      );
      expect(
        String.fromCharCodes(bytes),
        isNot(contains('message-id-sensitive')),
      );
      expect(secrets.data.keys, ['chatprefskey:alice']);
      await p.close();
      final reopened = await LocalChatPreferences.open(
        dir: dir,
        secrets: secrets,
        uid: 'alice',
      );
      expect(reopened.seen['chat-sensitive-name'], {'message-id-sensitive'});
      expect(reopened.muted, {'chat-sensitive-name'});
      expect(reopened.previewText, isTrue);
      await reopened.close();
      bytes[bytes.length - 1] ^= 1;
      await File('${dir.path}/chat-ui.enc').writeAsBytes(bytes);
      final damaged = await LocalChatPreferences.open(
        dir: dir,
        secrets: secrets,
        uid: 'alice',
      );
      expect(damaged.available, isFalse);
      expect(damaged.seen, isEmpty);
      expect(damaged.previewText, isFalse);
      await expectLater(damaged.mute('new-chat', true), throwsStateError);
      await damaged.reset();
      expect(damaged.available, isTrue);
      await damaged.mute('new-chat', true);
      await damaged.close();
      final repaired = await LocalChatPreferences.open(
        dir: dir,
        secrets: secrets,
        uid: 'alice',
      );
      expect(repaired.available, isTrue);
      expect(repaired.muted, {'new-chat'});
      await repaired.close();
    },
  );
  test('account binding prevents opening another account data', () async {
    final dir = await Directory.systemTemp.createTemp('fireplace-prefs-');
    addTearDown(() => dir.delete(recursive: true));
    final secrets = MemorySecretStore();
    final p = await LocalChatPreferences.open(
      dir: dir,
      secrets: secrets,
      uid: 'alice',
    );
    await p.mute('private-chat', true);
    await p.close();
    // Even giving another account the same key must not bypass authenticated UID binding.
    secrets.data['chatprefskey:bob'] = secrets.data['chatprefskey:alice']!;
    final wrongAccount = await LocalChatPreferences.open(
      dir: dir,
      secrets: secrets,
      uid: 'bob',
    );
    expect(wrongAccount.available, isFalse);
    expect(wrongAccount.muted, isEmpty);
    expect(wrongAccount.seen, isEmpty);
    await wrongAccount.close();
  });
  test('write failure rolls back and later queued writes still work', () async {
    var fail = true;
    final p = LocalChatPreferences(
      save: (_) async {
        if (fail) throw StateError('disk full');
      },
    );
    addTearDown(p.close);
    await expectLater(p.mute('a', true), throwsStateError);
    expect(p.muted, isEmpty);
    fail = false;
    await p.mute('b', true);
    expect(p.muted, {'b'});
  });
  test(
    'writes serialize; seen IDs survive concurrent mute and preview updates',
    () async {
      final hold = Completer<void>();
      var calls = 0;
      final p = LocalChatPreferences(
        save: (_) async {
          calls++;
          if (calls == 1) await hold.future;
        },
      );
      final seen = p.markSeen('a', ['1', '2']);
      final mute = p.mute('a', true);
      final preview = p.previews(true);
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      hold.complete();
      await Future.wait([seen, mute, preview]);
      expect(p.seen['a'], {'1', '2'});
      expect(p.muted, {'a'});
      expect(p.previewText, isTrue);
      await p.close();
      await p.close();
      await expectLater(p.mute('b', true), throwsStateError);
    },
  );
}
