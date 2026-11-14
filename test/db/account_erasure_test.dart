import 'dart:convert';
import 'dart:io';

import 'package:fireplace/src/db/account_erasure.dart';
import 'package:fireplace/src/db/secret_store.dart';
import 'package:fireplace/src/db/shared_lock.dart';
import 'package:flutter_test/flutter_test.dart';

class _FailOnce extends MemorySecretStore {
  String? fail;
  @override
  Future<void> delete(String key) async {
    if (key == fail) {
      fail = null;
      throw StateError('keychain unavailable');
    }
    await super.delete(key);
  }
}

void main() {
  test('all owned key families are erased, including device sessions and account settings', () async {
    final store = MemorySecretStore();
    final owned = <String, String>{
      for (final kind in [
        'identity',
        'bundle',
        'msgkey',
        'chatprefskey',
        'hidden',
        'pushasked',
        'pushoff',
        'pushnopreview',
        'pushhidename',
        'pushsilent',
        'pushchats',
      ])
        '$kind:alice': 'owned',
      'device:alice': jsonEncode({'deviceId': 'alice-device'}),
      'prekeys:alice:alice-device': 'private prekeys',
      'prekeys:alice:older-device': 'old private prekeys',
      'sess:alice-device:bob:bob-device': 'session',
      'sess:older-device:bob:bob-device': 'old session',
      'cursor:alice-device:alice_bob': 'cursor',
      'journal:alice-device': 'message journal',
      'journal:alice-device:alice_bob:message': 'legacy journal',
      'journals:alice-device': 'legacy index',
      for (final kind in ['pin', 'known', 'verified'])
        '$kind:account:["alice","bob"]': 'contact trust',
      for (final kind in ['theme-mode', 'chat-colors', 'send-sound'])
        'ui:$kind:account:alice': 'setting',
      'ios-preview-auth': jsonEncode({'uid': 'alice', 'token': 'fictional'}),
    };
    final other = <String, String>{
      'identity:alice2': 'different account',
      'device:bob': jsonEncode({'deviceId': 'bob-device'}),
      'prekeys:bob:bob-device': 'bob prekeys',
      'sess:bob-device:alice:alice-device': 'bob session containing alice',
      'cursor:bob-device:alice_bob': 'bob cursor',
      'journal:bob-device': 'bob journal',
      'pin:account:["bob","alice"]': 'bob trust',
      'ui:theme-mode:account:bob': 'dark',
    };
    store.data
      ..addAll(owned)
      ..addAll(other);
    await eraseAccountSecrets(store, 'alice');
    expect(store.data, other);
    await eraseAccountSecrets(store, 'alice');
    expect(store.data, other);
  });

  test(
    'a failed keychain erase retains ownership anchors and resumes safely',
    () async {
      final store = _FailOnce()..fail = 'cursor:own-device:alice_bob';
      store.data.addAll({
        'device:alice': '{"deviceId":"own-device"}',
        'identity:alice': 'identity',
        'sess:own-device:bob:peer': 'session',
        'cursor:own-device:alice_bob': 'cursor',
        'journal:own-device': 'plaintext journal',
        'identity:bob': 'keep',
      });
      await expectLater(eraseAccountSecrets(store, 'alice'), throwsStateError);
      expect(store.data['device:alice'], isNotNull);
      await eraseAccountSecrets(store, 'alice');
      expect(store.data, {'identity:bob': 'keep'});
    },
  );

  test('another active account preview credential is preserved', () async {
    final store = MemorySecretStore()
      ..data['ios-preview-auth'] = '{"uid":"bob"}';
    await eraseAccountSecrets(store, 'alice');
    expect(store.data, {'ios-preview-auth': '{"uid":"bob"}'});
  });

  test('old device prekeys remain an ownership anchor until derived erasure succeeds', () async {
    final store = _FailOnce()..fail = 'cursor:old-device:alice_bob';
    store.data.addAll({
      'device:alice': '{"deviceId":"current-device"}',
      'prekeys:alice:old-device': 'old private prekeys',
      'cursor:old-device:alice_bob': 'cursor',
      'sess:old-device:bob:peer': 'session',
      'identity:bob': 'keep',
    });
    await expectLater(eraseAccountSecrets(store, 'alice'), throwsStateError);
    expect(store.data['prekeys:alice:old-device'], isNotNull);
    await eraseAccountSecrets(store, 'alice');
    expect(store.data, {'identity:bob': 'keep'});
  });

  test('erase both history locations without opening a session, preserving sibling accounts', () async {
    final root = await Directory.systemTemp.createTemp('fireplace-delete-');
    addTearDown(() => root.delete(recursive: true));
    final roots = [
      Directory('${root.path}/documents'),
      Directory('${root.path}/shared'),
    ];
    for (final parent in roots) {
      for (final uid in ['alice', 'alice2', 'bob']) {
        final dir = await Directory('${parent.path}/messages_$uid')
            .create(recursive: true);
        for (final name in [
          'history.enc',
          'history.log',
          'chat-ui.enc',
          'chat-ui.enc.tmp',
          'lock.gen',
        ]) {
          await File('${dir.path}/$name').writeAsString(uid);
        }
      }
    }
    await eraseAccountHistory(
      uid: 'alice',
      roots: roots,
      lockFor: (_) => SharedLock(),
    );
    await eraseAccountHistory(
      uid: 'alice',
      roots: roots,
      lockFor: (_) => SharedLock(),
    );
    for (final parent in roots) {
      expect(
        await Directory('${parent.path}/messages_alice').exists(),
        isFalse,
      );
      for (final uid in ['alice2', 'bob']) {
        expect(
          await File('${parent.path}/messages_$uid/history.enc').readAsString(),
          uid,
        );
      }
    }
    await expectLater(
      eraseAccountHistory(
        uid: '../bob',
        roots: roots,
        lockFor: (_) => SharedLock(),
      ),
      throwsStateError,
    );
  });
}
