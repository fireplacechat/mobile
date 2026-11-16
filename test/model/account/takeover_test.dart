// Starting fresh with a wait (decision 0063): what the app writes and reads,
// and the proof a device attaches to its requests.
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/src/crypto/codec.dart';
import 'package:fireplace/src/crypto/device_proof.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/model/account/takeover.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the server does with its own key and the device's published key.
Future<List<int>> serverSide({
  required List<int> serverSeed,
  required List<int> serverPub,
  required List<int> devicePub,
  required Uint8List message,
}) async {
  final x = X25519();
  final shared = await (await x.sharedSecretKey(
    keyPair: await x.newKeyPairFromSeed(serverSeed),
    remotePublicKey: SimplePublicKey(devicePub, type: KeyPairType.x25519),
  )).extractBytes();
  final key = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
    secretKey: SecretKey(shared),
    nonce: const <int>[],
    info: lp([utf8Bytes('fireplace/v1/device-proof'), devicePub, serverPub]),
  );
  return (await Hmac.sha256().calculateMac(message, secretKey: key)).bytes;
}

void main() {
  group('device proof', () {
    final deviceSeed = List.generate(32, (i) => i * 7 + 1);
    final serverSeed = List.generate(32, (i) => 250 - i * 3);
    late List<int> devicePub, serverPub;

    setUp(() async {
      final x = X25519();
      devicePub = (await (await x.newKeyPairFromSeed(
        deviceSeed,
      )).extractPublicKey()).bytes;
      serverPub = (await (await x.newKeyPairFromSeed(
        serverSeed,
      )).extractPublicKey()).bytes;
    });

    Uint8List message({
      String uid = 'alice',
      String device = 'device-0001',
      String id = 'request-1',
      String kind = 'stop',
      List<String> arguments = const [],
    }) => DeviceProof.message(
      uid: uid,
      deviceId: device,
      requestId: id,
      kind: kind,
      arguments: arguments,
    );

    test('the server computes the same proof from the published key', () async {
      final made = await DeviceProof.make(
        deviceSeed: deviceSeed,
        devicePub: devicePub,
        serverPub: serverPub,
        message: message(),
      );
      expect(made, hasLength(32));
      expect(
        made,
        await serverSide(
          serverSeed: serverSeed,
          serverPub: serverPub,
          devicePub: devicePub,
          message: message(),
        ),
      );
    });

    test(
      'a proof belongs to one account, device, request and action',
      () async {
        Future<String> proof(Uint8List m, {List<int>? seed}) async => b64(
          await DeviceProof.make(
            deviceSeed: seed ?? deviceSeed,
            devicePub: devicePub,
            serverPub: serverPub,
            message: m,
          ),
        );
        final base = await proof(message());
        final others = [
          await proof(message(uid: 'mallory')),
          await proof(message(device: 'device-0002')),
          await proof(message(id: 'request-2')),
          await proof(message(kind: 'setWait')),
          await proof(message(arguments: ['1'])),
          // Another device's key, the same request.
          await proof(message(), seed: List.filled(32, 9)),
        ];
        expect(others, isNot(contains(base)));
        expect(others.toSet(), hasLength(others.length));
        // Fields cannot run into each other.
        expect(
          await proof(message(kind: 'set', arguments: ['Wait'])),
          isNot(await proof(message(kind: 'setWait'))),
        );
      },
    );

    test('a server key that gives no shared secret is refused', () async {
      await expectLater(
        DeviceProof.make(
          deviceSeed: deviceSeed,
          devicePub: devicePub,
          serverPub: Uint8List(32),
          message: message(),
        ),
        throwsArgumentError,
      );
    });
  });

  group('requests', () {
    late FakeFirebaseFirestore db;
    late TakeoverService service;
    setUp(() {
      db = FakeFirebaseFirestore();
      // No request here needs the password check.
      service = TakeoverService(db, _NoAuth());
    });

    test('the wait is three days unless the account says otherwise', () async {
      expect(await service.wait('alice'), LostPhoneWait.threeDays);
      await db.doc('users/alice/private/security').set({'waitDays': 14});
      expect(await service.wait('alice'), LostPhoneWait.twoWeeks);
      await db.doc('users/alice/private/security').set({'waitDays': 5});
      expect(await service.wait('alice'), LostPhoneWait.threeDays);
    });

    test('starting records the wait and when it ends; withdrawing removes '
        'it', () async {
      await db.doc('users/alice/private/security').set({'waitDays': 7});
      expect(await service.pending('alice'), isNull);
      final seen = <PendingStart?>[];
      final sub = service.watch('alice').listen(seen.add);
      final made = await service.start('alice');
      expect(made.readyAt.difference(made.startedAt), const Duration(days: 7));
      expect(made.readyBy(made.startedAt), isFalse);
      expect(made.readyBy(made.readyAt), isTrue);
      final stored = (await db.doc('users/alice/private/startFresh').get())
          .data()!;
      expect(stored.keys.toSet(), {'startedAt', 'waitDays', 'session'});
      expect(stored['session'], 1700000000);
      expect(stored['startedAt'], isA<Timestamp>());
      await service.withdraw('alice');
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(seen.first, isNull);
      expect(seen.last, isNull);
      expect(seen.whereType<PendingStart>(), hasLength(1));
    });

    test('an account without a device has nobody to warn', () async {
      expect(await service.hasDevices('alice'), isFalse);
      await db.doc('users/alice/devices/device-0001').set({'x': 1});
      expect(await service.hasDevices('alice'), isTrue);
    });

    test('a device request carries a proof the server can check, and waits '
        'for its answer', () async {
      final serverSeed = List.generate(32, (i) => 250 - i * 3);
      final serverPub = (await (await X25519().newKeyPairFromSeed(
        serverSeed,
      )).extractPublicKey()).bytes;
      await db.doc('config/deviceProof').set({
        'x25519Pub': base64Encode(serverPub),
      });
      final device = await KeyService(
        db,
        MemorySecretStore(),
      ).ensureDevice('alice');

      // The server's part: check the proof against the device's published
      // key, then answer.
      var accept = true;
      final checked = <bool>[];
      final sub = db.collection('users/alice/accountOps').snapshots().listen((
        snap,
      ) async {
        for (final doc in snap.docs) {
          final data = doc.data();
          if (data['status'] != null) continue;
          final published =
              (await db.doc('users/alice/devices/${data['device']}').get())
                  .data()!;
          final expected = await serverSide(
            serverSeed: serverSeed,
            serverPub: serverPub,
            devicePub: base64Decode(published['x25519Pub'] as String),
            message: DeviceProof.message(
              uid: 'alice',
              deviceId: data['device'] as String,
              requestId: doc.id,
              kind: data['kind'] as String,
              arguments: ['${data['waitDays']}'],
            ),
          );
          final ok = b64(expected) == data['proof'];
          checked.add(ok);
          await doc.reference.update({
            'status': ok && accept ? 'done' : 'refused',
          });
        }
      });

      await service.setWait('alice', device, LostPhoneWait.oneWeek);
      expect(checked, [true]);
      final sent = (await db.collection('users/alice/accountOps').get())
          .docs
          .single
          .data();
      expect(sent['kind'], 'setWait');
      expect(sent['waitDays'], 7);
      expect(sent['device'], device.keys.deviceId);
      // Nothing of the device's secret key is in the request.
      expect(
        jsonEncode(sent.map((k, v) => MapEntry(k, '$v'))),
        isNot(contains(b64(device.keys.x25519Seed))),
      );

      accept = false;
      await expectLater(
        service.setWait('alice', device, LostPhoneWait.oneDay),
        throwsA(isA<TakeoverException>()),
      );
      await sub.cancel();

      // Nobody answers: the outcome is reported as unknown, not as done.
      final quick = TakeoverService(
        db,
        _NoAuth(),
        timeout: const Duration(milliseconds: 50),
      );
      await expectLater(
        quick.setWait('alice', device, LostPhoneWait.oneDay),
        throwsA(isA<TakeoverException>()),
      );
    });
  });
}

class _NoAuth extends Fake implements AuthService {
  @override
  Future<int> signInTime() async => 1700000000;
}
