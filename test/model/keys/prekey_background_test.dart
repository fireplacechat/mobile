import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'prekey_test.dart' show Phone;

Future<Set<String>> heldOneTime(Phone p) async {
  final raw = await p.secrets.read(
    'prekeys:${p.uid}:${p.device.keys.deviceId}',
  );
  return ((jsonDecode(raw!) as Map)['oneTime'] as Map).keys
      .cast<String>()
      .toSet();
}

void main() {
  test('a new device has no signed prekey until upkeep first runs', () async {
    final db = FakeFirebaseFirestore();
    final p = await Phone.create(db, 'bob', publishPrekeys: false);
    expect(
      await p.prekeys.hasSignedPreKey('bob', p.device.keys.deviceId),
      isFalse,
    );
    await p.prekeys.maintain('bob', p.device);
    expect(
      await p.prekeys.hasSignedPreKey('bob', p.device.keys.deviceId),
      isTrue,
    );
  });

  test('a one-time prekey used while upkeep runs stays used', () async {
    final db = FakeFirebaseFirestore();
    final p = await Phone.create(db, 'bob');
    final deviceId = p.device.keys.deviceId;
    // Empty the published pool so upkeep refills it, which takes many steps.
    for (final d in (await p.prekeyCol.get()).docs) {
      await d.reference.delete();
    }
    final used = (await heldOneTime(p)).first;
    final upkeep = p.prekeys.maintain('bob', p.device);
    // A handshake arrives and spends one of the keys while upkeep is running.
    await p.prekeys.consumeOneTime('bob', deviceId, used);
    await upkeep;
    expect(await heldOneTime(p), isNot(contains(used)));
  });

  test('two upkeep calls at once share one run', () async {
    final db = FakeFirebaseFirestore();
    final p = await Phone.create(db, 'bob');
    for (final d in (await p.prekeyCol.get()).docs) {
      await d.reference.delete();
    }
    await Future.wait([
      p.prekeys.maintain('bob', p.device),
      p.prekeys.maintain('bob', p.device),
    ]);
    final published = (await p.prekeyCol.get()).docs
        .where((d) => d.data()['kind'] == 'onetime')
        .length;
    expect(published, PreKeyService.poolTarget);
  });

  test('upkeep stops writing once the session has closed', () async {
    final db = FakeFirebaseFirestore();
    final p = await Phone.create(db, 'bob');
    for (final d in (await p.prekeyCol.get()).docs) {
      await d.reference.delete();
    }
    final before = await p.secrets.read(
      'prekeys:bob:${p.device.keys.deviceId}',
    );
    await p.prekeys.maintain('bob', p.device, isStopped: () => true);
    expect(
      await p.secrets.read('prekeys:bob:${p.device.keys.deviceId}'),
      before,
    );
  });
}
