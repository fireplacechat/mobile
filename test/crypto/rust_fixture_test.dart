import 'dart:convert';
import 'dart:io';

import 'package:fireplace/src/crypto/session.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Rust core produced this file (see fireplace-crypto). The app cannot
/// depend on that crate until 0.1.0 is published, so this test opens the
/// committed result with the Dart implementation.
void main() {
  test(
    'Dart decrypts a session and a reply produced by the Rust core',
    () async {
      final doc = jsonDecode(
        File('test/crypto/vectors/rust_session.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final chatId = doc['chatId'] as String;

      final bob = Session.fromJson(
        jsonDecode(doc['bobSession'] as String) as Map<String, dynamic>,
      );
      final envelope = Envelope.fromJson(
        jsonDecode(doc['envelope'] as String) as Map<String, dynamic>,
      );
      final plain = await bob.decrypt(envelope, chatId: chatId);
      expect(utf8.decode(plain), doc['plaintext']);

      final alice = Session.fromJson(
        jsonDecode(doc['aliceSession'] as String) as Map<String, dynamic>,
      );
      final reply = Envelope.fromJson(
        jsonDecode(doc['reply'] as String) as Map<String, dynamic>,
      );
      final back = await alice.decrypt(reply, chatId: chatId);
      expect(utf8.decode(back), doc['replyPlaintext']);
    },
  );
}
