import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import '../support/crypto_backend.dart';
import 'protocol_property_test.dart' as properties;

void main() {
  late properties.Party alice, bob;
  setUpAll(() async {
    useRust = false;
    alice = await properties.Party.create('alice');
    useRust = true;
    bob = await properties.Party.create('bob');
  });
  tearDown(() {
    closeNativeSessions();
    initiateWithRust = null;
    acceptWithRust = null;
    reloadWithRust = null;
  });

  for (final rustInitiator in [false, true]) {
    final direction = rustInitiator
        ? 'Rust initiates, Dart accepts'
        : 'Dart initiates, Rust accepts';
    test('$direction: skipped keys and session transfer in both directions', () async {
      initiateWithRust = rustInitiator;
      acceptWithRust = !rustInitiator;
      var (a, b, _) = await properties.pair(alice, bob);
      final first = await a.encrypt(utf8.encode('first'), chatId: 'c');
      final second = await a.encrypt(utf8.encode('second'), chatId: 'c');
      expect(utf8.decode(await b.decrypt(second, chatId: 'c')), 'second');
      // Transfer the receiver with an unconsumed skipped key to the other core.
      useRust = rustInitiator;
      b = Session.fromJson(jsonDecode(jsonEncode(b.toJson())));
      expect(utf8.decode(await b.decrypt(first, chatId: 'c')), 'first');
      await expectLater(
        b.decrypt(first, chatId: 'c'),
        throwsA(isA<SessionException>()),
      );
      final reply = await b.encrypt(utf8.encode('reply'), chatId: 'c');
      useRust = !rustInitiator;
      a = Session.fromJson(jsonDecode(jsonEncode(a.toJson())));
      expect(utf8.decode(await a.decrypt(reply, chatId: 'c')), 'reply');
      final next = await a.encrypt(utf8.encode('after transfer'), chatId: 'c');
      expect(utf8.decode(await b.decrypt(next, chatId: 'c')), 'after transfer');
      expect(await a.selfCheck(), isTrue);
      expect(await b.selfCheck(), isTrue);
    });

    for (var seed = 2001; seed <= 2010; seed++) {
      test(
        '$direction: adversarial schedule $seed with backend changes on restart',
        () async {
          initiateWithRust = rustInitiator;
          acceptWithRust = !rustInitiator;
          final schedule = Random(seed ^ 0x7f12);
          reloadWithRust = schedule.nextBool;
          await properties.simulate(seed, alice, bob);
        },
      );
    }
  }
}
