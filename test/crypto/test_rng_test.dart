import 'dart:convert';
import 'dart:typed_data';

import 'package:fireplace/src/crypto/codec.dart';
import 'package:fireplace/src/crypto/device.dart';
import 'package:fireplace/src/crypto/identity.dart';
import 'package:fireplace/src/crypto/link.dart';
import 'package:fireplace/src/crypto/prekeys.dart';
import 'package:fireplace/src/crypto/recovery.dart';
import 'package:fireplace/src/crypto/session.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _pattern() =>
    Uint8List.fromList(List<int>.generate(8192, (i) => (i * 17 + 3) & 0xff));

Future<String> _scripted() async {
  installTestRng(_pattern());
  final now = DateTime.fromMillisecondsSinceEpoch(1700000000000);
  final aliceId = await AccountIdentity.generate();
  final aliceKeys = await DeviceKeys.generate();
  final alice = await aliceKeys.certify(aliceId, 'alice');
  final bobId = await AccountIdentity.generate();
  final bobKeys = await DeviceKeys.generate();
  final bob = await bobKeys.certify(bobId, 'bob');
  final signed = await PreKeyRecord.generate(now: now);
  final published = await PreKeys.sign(signed, bobId, 'bob', bobKeys.deviceId);
  final once = await PreKeyRecord.generate(now: now);
  final (session, handshake) = await Session.initiate(
    local: aliceKeys,
    localBundle: alice,
    remote: PreKeyBundle(
      device: bob,
      signed: published,
      oneTime: PreKeys.oneTime(once),
    ),
  );
  final envelope = await session.encrypt(
    utf8.encode('hello'),
    chatId: 'chat-1',
  );
  final stored = session.toJson();
  stored['createdAt'] = 0;
  return jsonEncode({
    'identity': aliceId.toJson(),
    'device': aliceKeys.toJson(),
    'handshake': handshake.toJson(),
    'session': stored,
    'envelope': envelope.toJson(),
  });
}

void main() {
  tearDown(() => installTestRng(null));

  test(
    'the generator stays the operating system until a test installs a stream',
    () async {
      final first = (await AccountIdentity.generate()).toJson()['edSeed'];
      final second = (await AccountIdentity.generate()).toJson()['edSeed'];
      expect(first, isNot(second));
    },
  );

  test('one recorded stream repeats the handshake byte for byte', () async {
    expect(await _scripted(), await _scripted());
  });

  test(
    'a short stream fails instead of reading the operating system',
    () async {
      installTestRng(Uint8List(8));
      await expectLater(AccountIdentity.generate(), throwsStateError);
    },
  );

  test('these JSON formats contain no floats', () async {
    installTestRng(_pattern());
    final now = DateTime.fromMillisecondsSinceEpoch(1700000000000);
    final aliceId = await AccountIdentity.generate();
    final aliceKeys = await DeviceKeys.generate();
    final alice = await aliceKeys.certify(aliceId, 'alice');
    final bobId = await AccountIdentity.generate();
    final bobKeys = await DeviceKeys.generate();
    final bob = await bobKeys.certify(bobId, 'bob');
    final record = await PreKeyRecord.generate(now: now);
    final signed = await PreKeys.sign(record, bobId, 'bob', bobKeys.deviceId);
    final once = await PreKeyRecord.generate(now: now);
    final publishedOnce = PreKeys.oneTime(once);
    final (session, handshake) = await Session.initiate(
      local: aliceKeys,
      localBundle: alice,
      remote: PreKeyBundle(device: bob, signed: signed, oneTime: publishedOnce),
    );
    final envelope = await session.encrypt(
      utf8.encode('hello'),
      chatId: 'chat-1',
    );
    final sealed = await LinkCrypto.seal(
      aliceId,
      uid: 'ada',
      deviceId: aliceKeys.deviceId,
      x25519Pub: aliceKeys.x25519Pub,
      kemPub: aliceKeys.kemPub,
    );
    final key = RecoveryKey.generate();
    final docs = <String, Object>{
      'identity': aliceId.toJson(),
      'device': aliceKeys.toJson(),
      'bundle': {
        'uid': alice.uid,
        'deviceId': alice.deviceId,
        ...alice.toFirestore(),
      },
      'prekey': record.toJson(),
      'signed': {'id': signed.id, ...signed.toFirestore()},
      'oneTime': {'id': publishedOnce.id, ...publishedOnce.toFirestore()},
      'handshake': handshake.toJson(),
      'session': session.toJson(),
      'envelope': envelope.toJson(),
      'sealed': sealed.toJson(),
      'recoveryPlaintext': jsonDecode(jsonEncode(aliceId.toJson())),
    };
    // The backup encrypts that identity JSON. The blob itself is not JSON.
    expect(await RecoveryBackup.encrypt(aliceId, key), isA<String>());

    void walk(Object? value, String path) {
      if (value is double) {
        fail('$path is a float');
      } else if (value is Map) {
        for (final entry in value.entries) {
          walk(entry.value, '$path.${entry.key}');
        }
      } else if (value is List) {
        for (var i = 0; i < value.length; i++) {
          walk(value[i], '$path[$i]');
        }
      }
    }

    for (final entry in docs.entries) {
      walk(entry.value, entry.key);
      walk(jsonDecode(jsonEncode(entry.value)), 'encoded ${entry.key}');
    }
  });
}
