import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_crypto.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:flutter_test/flutter_test.dart';

// Redirect only this zone's host-library lookup. No process-wide directory or
// platform override, production injection hook or real keychain is involved.
class _MissingLibraryFile extends Fake implements File {
  @override
  File get absolute => this;
  @override
  String get path => 'build/fireplace_crypto/unavailable-startup-test-library';
}

void main() {
  for (final reset in [false, true]) {
    test(
      reset
          ? 'unavailable crypto cannot delete keys or backup during reset'
          : 'unavailable crypto is not classified as missing local keys',
      () async {
        final db = FakeFirebaseFirestore();
        final store = MemorySecretStore();
        await CryptoBackend.runWith(CryptoBackendKind.dart, () async {
          final keys = KeyService(db, store);
          final device = await keys.ensureDevice('alice');
          await RecoveryService(
            db,
            store,
            keys,
          ).createBackup('alice', device.identity);
        });
        final localBefore = Map.of(store.data);
        final remoteBefore = db.dump();

        await IOOverrides.runZoned(() async {
          final keys = KeyService(db, store);
          await expectLater(
            CryptoBackend.runWith(
              CryptoBackendKind.rust,
              () => reset
                  ? RecoveryService(db, store, keys).resetIdentity('alice')
                  : keys.ensureDevice('alice'),
            ),
            throwsA(isA<ArgumentError>()),
          );
        }, createFile: (_) => _MissingLibraryFile());

        expect(store.data.keys, unorderedEquals(localBefore.keys));
        for (final entry in localBefore.entries) {
          expect(store.data[entry.key] == entry.value, isTrue);
        }
        expect(db.dump() == remoteBefore, isTrue);
      },
    );
  }
}
