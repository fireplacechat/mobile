import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/fireplace_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../services/durability_test.dart' show Phone;

class _ChangedKeys extends Fake implements KeyService {
  @override
  Future<List<DeviceBundle>> fetchDevices(String uid) =>
      Future.error(IdentityChangedException(uid, List.filled(64, 1)));
}

void main() {
  test('block changes survive a paused initial snapshot', () async {
    final safety = SafetyService(
      FakeFirebaseFirestore(),
      MemorySecretStore(),
      'owner',
    );
    await safety.start();
    addTearDown(safety.dispose);
    final events = StreamIterator(safety.watchBlocked());
    addTearDown(events.cancel);
    expect(await events.moveNext(), isTrue);
    expect(events.current, isEmpty);
    await safety.block('fred');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    for (var i = 0; i < 4; i++) {
      expect(
        await events.moveNext().timeout(const Duration(seconds: 1)),
        isTrue,
      );
      if (events.current.contains('fred')) return;
    }
    fail('The block update was lost between initial snapshot and subscription');
  });

  test('identity alerts survive a paused initial snapshot', () async {
    final db = FakeFirebaseFirestore();
    final phone = await Phone.create(db, 'owner');
    final chat = ChatService(
      db: db,
      uid: 'owner',
      device: phone.device,
      keys: _ChangedKeys(),
      prekeys: phone.prekeys,
      secrets: phone.secrets,
      messages: phone.messages,
    );
    final events = StreamIterator(chat.watchIdentityAlerts());
    addTearDown(events.cancel);
    expect(await events.moveNext(), isTrue);
    expect(events.current, isEmpty);
    await expectLater(
      chat.sendText('owner_fred', 'hi'),
      throwsA(isA<IdentityChangedException>()),
    );
    expect(chat.identityAlerts.keys, contains('fred'));
    expect(await events.moveNext().timeout(const Duration(seconds: 1)), isTrue);
    expect(events.current.keys, contains('fred'));
    expect(await phone.bodies('owner_fred'), isEmpty);
  });
}
