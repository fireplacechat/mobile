import 'dart:convert';
import 'dart:typed_data';

import 'package:fireplace/fireplace_crypto.dart' as reference;
import 'package:fireplace_native/fireplace_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/crypto_backend.dart';
import 'protocol_property_test.dart' as properties;

void main() {
  tearDown(closeNativeSessions);

  test('native outputs stay usable after later calls and failed calls', () {
    final identity = nativeCrypto.identityGenerate();
    final public = nativeCrypto.identityPublic(identity);
    final saved = Uint8List.fromList(public);
    expect(
      () => nativeCrypto.identityPublic({}),
      throwsA(isA<NativeCryptoException>()),
    );
    expect(
      () => nativeCrypto.identitySign(identity, Uint8List(4 * 1024 * 1024 + 1)),
      throwsFormatException,
    );
    final message = utf8.encode('fictional signature probe');
    final signature = nativeCrypto.identitySign(identity, message);
    expect(nativeCrypto.identityVerify(public, message, signature), isTrue);
    expect(public, saved);
    expect(nativeCrypto.identityVerify(public, message, [1, 2, 3]), isFalse);
  });

  test('native sessions own their state, close explicitly, and reject use after close', () async {
    useRust = true;
    final alice = await properties.Party.create('alice');
    final bob = await properties.Party.create('bob');
    final (sender, _, _) = await properties.pair(alice, bob);
    final live = nativeCrypto.loadSession(sender.toJson());
    addTearDown(live.close);
    final snapshot = live.toJson();
    (snapshot['st'] as Map)['ns'] = 9999;
    snapshot['localUid'] = 'changed snapshot';
    final envelope = live.encrypt(utf8.encode('snapshot independence'), 'c');
    expect(envelope['n'], 0);
    expect(live.toJson()['localUid'], 'alice');
    expect((live.toJson()['st'] as Map)['ns'], 1);
    // Loading and exporting a handle never adds transient state to stored JSON.
    expect(reference.Session.tryFromJson(live.toJson()), isNotNull);
    live.close();
    live.close();
    expect(live.toJson, throwsStateError);
    expect(() => live.encrypt([1], 'c'), throwsStateError);
    expect(() => live.decrypt(envelope, 'c'), throwsStateError);
  });
}
