// Writes the known-answer files the Rust core checks.
//
// Run from the app root. Asserts must be on, or the recorded stream is ignored:
//   dart run --enable-asserts scripts/export_crypto_vectors.dart <output-directory>
//
// The scripted sections share one recorded byte stream, in the same order the
// Rust test replays. The natural section leaves the stream off, so its
// handshake is cross-checked (Rust opens it) rather than compared byte for byte.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fireplace/src/crypto/codec.dart';
import 'package:fireplace/src/crypto/device.dart';
import 'package:fireplace/src/crypto/identity.dart';
import 'package:fireplace/src/crypto/link.dart';
import 'package:fireplace/src/crypto/prekeys.dart';
import 'package:fireplace/src/crypto/recovery.dart';
import 'package:fireplace/src/crypto/session.dart';

Uint8List pattern() =>
    Uint8List.fromList(List<int>.generate(8192, (i) => (i * 17 + 3) & 0xff));

String bundleJson(DeviceBundle bundle) => jsonEncode({
  'uid': bundle.uid,
  'deviceId': bundle.deviceId,
  'x25519Pub': b64(bundle.x25519Pub),
  'kemPub': b64(bundle.kemPub),
  'identityPub': b64(bundle.identityPub),
  'cert': b64(bundle.cert),
});

String publishedJson(PublishedPreKey prekey) => jsonEncode({
  'id': prekey.id,
  'kind': prekey.kind == PreKeyKind.signed ? 'signed' : 'onetime',
  'x25519Pub': b64(prekey.x25519Pub),
  'kemPub': b64(prekey.kemPub),
  if (prekey.sig != null) 'sig': b64(prekey.sig!),
});

Future<Map<String, Object>> scriptedHandshake() async {
  installTestRng(pattern());
  const prekeyNow = 1700000000000;
  final now = DateTime.fromMillisecondsSinceEpoch(prekeyNow);
  final aliceId = await AccountIdentity.generate();
  final aliceKeys = await DeviceKeys.generate();
  final alice = await aliceKeys.certify(aliceId, 'alice');
  final bobId = await AccountIdentity.generate();
  final bobKeys = await DeviceKeys.generate();
  final bob = await bobKeys.certify(bobId, 'bob');
  final signedRecord = await PreKeyRecord.generate(now: now);
  final signed = await PreKeys.sign(
    signedRecord,
    bobId,
    'bob',
    bobKeys.deviceId,
  );
  final oneTimeRecord = await PreKeyRecord.generate(now: now);
  final (aliceSession, handshake) = await Session.initiate(
    local: aliceKeys,
    localBundle: alice,
    remote: PreKeyBundle(
      device: bob,
      signed: signed,
      oneTime: PreKeys.oneTime(oneTimeRecord),
    ),
  );
  final bobSession = await Session.accept(
    local: bobKeys,
    localBundle: bob,
    remote: alice,
    handshake: handshake,
    signedPreKey: signedRecord,
    oneTimePreKey: oneTimeRecord,
  );
  final envelope = await aliceSession.encrypt(
    utf8.encode('hello'),
    chatId: 'chat-1',
  );
  installTestRng(null);
  return {
    'prekeyNow': prekeyNow,
    'aliceIdentity': jsonEncode(aliceId.toJson()),
    'aliceDevice': jsonEncode(aliceKeys.toJson()),
    'aliceBundle': bundleJson(alice),
    'bobIdentity': jsonEncode(bobId.toJson()),
    'bobDevice': jsonEncode(bobKeys.toJson()),
    'bobBundle': bundleJson(bob),
    'signedRecord': jsonEncode(signedRecord.toJson()),
    'signedPrekey': publishedJson(signed),
    'oneTimeRecord': jsonEncode(oneTimeRecord.toJson()),
    'oneTimePrekey': publishedJson(PreKeys.oneTime(oneTimeRecord)),
    'handshake': jsonEncode(handshake.toJson()),
    'aliceSession': jsonEncode(aliceSession.toJson()),
    'bobSession': jsonEncode(bobSession.toJson()),
    'envelope': jsonEncode(envelope.toJson()),
    'plaintext': 'hello',
    'chatId': 'chat-1',
  };
}

Future<Map<String, Object>> scriptedRecoveryAndLink() async {
  installTestRng(pattern());
  final identity = await AccountIdentity.generate();
  final key = RecoveryKey.generate();
  final blob = await RecoveryBackup.encrypt(identity, key);
  final device = await DeviceKeys.generate();
  final sealed = await LinkCrypto.seal(
    identity,
    uid: 'ada',
    deviceId: device.deviceId,
    x25519Pub: device.x25519Pub,
    kemPub: device.kemPub,
  );
  installTestRng(null);
  return {
    'identity': jsonEncode(identity.toJson()),
    'recoveryKey': b64(key.bytes),
    'display': await key.display(),
    'blob': blob,
    'device': jsonEncode(device.toJson()),
    'sealed': jsonEncode(sealed.toJson()),
    'uid': 'ada',
  };
}

Future<Map<String, Object>> naturalSession() async {
  installTestRng(null);
  const prekeyNow = 1700000000000;
  final now = DateTime.fromMillisecondsSinceEpoch(prekeyNow);
  final aliceId = await AccountIdentity.generate();
  final aliceKeys = await DeviceKeys.generate();
  final alice = await aliceKeys.certify(aliceId, 'alice');
  final bobId = await AccountIdentity.generate();
  final bobKeys = await DeviceKeys.generate();
  final bob = await bobKeys.certify(bobId, 'bob');
  final signedRecord = await PreKeyRecord.generate(now: now);
  final signed = await PreKeys.sign(
    signedRecord,
    bobId,
    'bob',
    bobKeys.deviceId,
  );
  final oneTimeRecord = await PreKeyRecord.generate(now: now);
  final (aliceSession, handshake) = await Session.initiate(
    local: aliceKeys,
    localBundle: alice,
    remote: PreKeyBundle(
      device: bob,
      signed: signed,
      oneTime: PreKeys.oneTime(oneTimeRecord),
    ),
  );
  final bobSession = await Session.accept(
    local: bobKeys,
    localBundle: bob,
    remote: alice,
    handshake: handshake,
    signedPreKey: signedRecord,
    oneTimePreKey: oneTimeRecord,
  );
  const plaintext = 'natural';
  final envelope = await aliceSession.encrypt(
    utf8.encode(plaintext),
    chatId: 'chat-1',
  );
  return {
    'bobSession': jsonEncode(bobSession.toJson()),
    'envelope': jsonEncode(envelope.toJson()),
    'plaintext': plaintext,
    'chatId': 'chat-1',
  };
}

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln(
      'usage: dart run scripts/export_crypto_vectors.dart <output-directory>',
    );
    exitCode = 64;
    return;
  }
  final dir = Directory(args[0]);
  await dir.create(recursive: true);
  final doc = {
    'pattern': 'byte i is (i * 17 + 3) mod 256, 8192 bytes',
    'handshake': await scriptedHandshake(),
    'recovery': await scriptedRecoveryAndLink(),
    'natural': await naturalSession(),
  };
  final file = File('${dir.path}/dart_vectors.json');
  await file.writeAsString('${jsonEncode(doc)}\n');
  stdout.writeln(file.path);
}
