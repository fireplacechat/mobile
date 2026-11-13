import 'dart:convert';
import 'dart:typed_data';

import 'package:fireplace/src/crypto/codec.dart';
import 'package:fireplace_native/fireplace_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../scripts/export_crypto_vectors.dart' as dart;
import '../support/native_test_rng.dart';

void main() {
  late NativeCrypto core;
  final sessions = <NativeSession>[];
  setUpAll(() => core = openTestRngCore());
  tearDown(() {
    installTestRng(null);
    nativeTestRng(core, null);
    for (final session in sessions) {
      session.close();
    }
    sessions.clear();
  });

  ({
    Map<String, dynamic> aliceId,
    Map<String, dynamic> aliceKeys,
    Map<String, dynamic> aliceBundle,
    Map<String, dynamic> bobId,
    Map<String, dynamic> bobKeys,
    Map<String, dynamic> bobBundle,
    Map<String, dynamic> signed,
    Map<String, dynamic> signedRecord,
    Map<String, dynamic> once,
    Map<String, dynamic> onceRecord,
    NativeSession alice,
    NativeSession bob,
    Map<String, dynamic> handshake,
  })
  pair() {
    nativeTestRng(core, dart.pattern());
    final aliceId = core.identityGenerate(), aliceKeys = core.deviceGenerate();
    final aliceBundle = core.deviceCertify(aliceKeys, aliceId, 'alice');
    final bobId = core.identityGenerate(), bobKeys = core.deviceGenerate();
    final bobBundle = core.deviceCertify(bobKeys, bobId, 'bob');
    final signedRecord = core.prekeyGenerate(1700000000000);
    final signed = core.prekeySign(
      signedRecord,
      bobId,
      'bob',
      bobKeys['deviceId'] as String,
    );
    final onceRecord = core.prekeyGenerate(1700000000000);
    final once = core.prekeyOneTime(onceRecord);
    final (alice, handshake) = core.initiate(aliceKeys, aliceBundle, {
      'device': bobBundle,
      'signed': signed,
      'oneTime': once,
    }, 1700000000000);
    sessions.add(alice);
    final bob = core.accept(
      bobKeys,
      bobBundle,
      aliceBundle,
      handshake,
      signedRecord,
      onceRecord,
      1700000000000,
    );
    sessions.add(bob);
    return (
      aliceId: aliceId,
      aliceKeys: aliceKeys,
      aliceBundle: aliceBundle,
      bobId: bobId,
      bobKeys: bobKeys,
      bobBundle: bobBundle,
      signed: signed,
      signedRecord: signedRecord,
      once: once,
      onceRecord: onceRecord,
      alice: alice,
      bob: bob,
      handshake: handshake,
    );
  }

  String normalized(String json) {
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    if (decoded.containsKey('st')) decoded['createdAt'] = 0;
    return jsonEncode(decoded);
  }

  void same(String name, Object expected, Object actual) {
    // Compare booleans so a failure never prints key material or session JSON.
    expect(
      actual == expected,
      isTrue,
      reason: '$name must match byte for byte',
    );
  }

  test('the C ABI matches the Dart handshake, keys, signatures and public codes byte for byte', () async {
    final expected = await dart.scriptedHandshake();
    final p = pair();
    final envelope = p.alice.encrypt(utf8.encode('hello'), 'chat-1');
    final actual = <String, Object>{
      'aliceIdentity': jsonEncode(p.aliceId),
      'aliceDevice': jsonEncode(p.aliceKeys),
      'aliceBundle': jsonEncode(p.aliceBundle),
      'bobIdentity': jsonEncode(p.bobId),
      'bobDevice': jsonEncode(p.bobKeys),
      'bobBundle': jsonEncode(p.bobBundle),
      'signedRecord': jsonEncode(p.signedRecord),
      'signedPrekey': jsonEncode(p.signed),
      'oneTimeRecord': jsonEncode(p.onceRecord),
      'oneTimePrekey': jsonEncode(p.once),
      'handshake': jsonEncode(p.handshake),
      'aliceSession': jsonEncode(p.alice.toJson()),
      'bobSession': jsonEncode(p.bob.toJson()),
      'envelope': jsonEncode(envelope),
      'aliceFingerprint': core.fingerprint(core.identityPublic(p.aliceId)),
      'bobFingerprint': core.fingerprint(core.identityPublic(p.bobId)),
      'safety': core.safetyNumber(
        core.identityPublic(p.aliceId),
        core.identityPublic(p.bobId),
      ),
      'safetySwapped': core.safetyNumber(
        core.identityPublic(p.bobId),
        core.identityPublic(p.aliceId),
      ),
      'linkFingerprint': core.linkFingerprint(
        unb64(p.bobKeys['x25519Pub']),
        unb64(p.bobKeys['kemPub']),
      ),
      'linkCode': core.linkConfirmation(
        core.identityPublic(p.aliceId),
        unb64(p.bobKeys['x25519Pub']),
        unb64(p.bobKeys['kemPub']),
      ),
    };
    for (final entry in actual.entries) {
      final value = expected[entry.key]!;
      same(
        entry.key,
        entry.key.endsWith('Session') ? normalized(value as String) : value,
        entry.key.endsWith('Session')
            ? normalized(entry.value as String)
            : entry.value,
      );
    }
  });

  test(
    'ratchet steps and skipped-key state match Dart byte for byte',
    () async {
      final expected = await dart.scriptedTranscript();
      final p = pair();
      final first = p.alice.encrypt(utf8.encode('one'), 'chat-1');
      final second = p.alice.encrypt(utf8.encode('two'), 'chat-1');
      same(
        'second plaintext',
        'two',
        utf8.decode(p.bob.decrypt(second, 'chat-1')),
      );
      final bobAfterSkip = jsonEncode(p.bob.toJson());
      same(
        'skipped plaintext',
        'one',
        utf8.decode(p.bob.decrypt(first, 'chat-1')),
      );
      final reply0 = p.bob.encrypt(utf8.encode('three'), 'chat-1');
      final reply1 = p.bob.encrypt(utf8.encode('four'), 'chat-1');
      final bobFinal = jsonEncode(p.bob.toJson());
      same(
        'reply plaintext',
        'four',
        utf8.decode(p.alice.decrypt(reply1, 'chat-1')),
      );
      final aliceAfterSkip = jsonEncode(p.alice.toJson());
      same(
        'skipped reply',
        'three',
        utf8.decode(p.alice.decrypt(reply0, 'chat-1')),
      );
      final actual = {
        'aliceToBob0': jsonEncode(first),
        'aliceToBob1': jsonEncode(second),
        'bobAfterSkip': bobAfterSkip,
        'bobToAlice0': jsonEncode(reply0),
        'bobToAlice1': jsonEncode(reply1),
        'bobFinal': bobFinal,
        'aliceAfterSkip': aliceAfterSkip,
        'aliceFinal': jsonEncode(p.alice.toJson()),
      };
      for (final entry in actual.entries) {
        same(
          entry.key,
          normalized(expected[entry.key]! as String),
          normalized(entry.value),
        );
      }
    },
  );

  test('recovery and linking match Dart byte for byte', () async {
    final expected = await dart.scriptedRecoveryAndLink();
    nativeTestRng(core, dart.pattern());
    final identity = core.identityGenerate();
    final key = core.recoveryGenerate();
    final blob = core.recoveryEncrypt(identity, key);
    final device = core.deviceGenerate();
    final sealed = core.linkSeal(
      identity,
      'ada',
      device['deviceId'] as String,
      unb64(device['x25519Pub']),
      unb64(device['kemPub']),
    );
    final actual = {
      'identity': jsonEncode(identity),
      'recoveryKey': b64(key),
      'display': core.recoveryDisplay(key),
      'blob': blob,
      'device': jsonEncode(device),
      'sealed': jsonEncode(sealed),
      'uid': 'ada',
    };
    for (final entry in actual.entries) {
      same(entry.key, expected[entry.key]!, entry.value);
    }
  });

  test(
    'an exhausted native random stream fails instead of falling back to the OS',
    () {
      nativeTestRng(core, Uint8List(8));
      expect(
        core.identityGenerate,
        throwsA(isA<NativeCryptoException>().having((e) => e.code, 'code', 5)),
      );
    },
  );
}
