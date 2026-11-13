import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/model/push/preview_credentials.dart';
import 'package:flutter_test/flutter_test.dart';

class DelayedCredentialStore extends MemorySecretStore {
  final started = Completer<void>(), finish = Completer<void>();
  @override
  Future<void> write(String key, String value) async {
    started.complete();
    await finish.future;
    await super.write(key, value);
  }
}

void main() {
  test('sign-out cannot be undone by a late token refresh', () async {
    final store = MemorySecretStore();
    final cache = PreviewCredentialCache(store);
    final token = Completer<String?>();
    final refresh = cache.update(() => token.future);
    await cache.clear();
    token.complete('fictional credential');
    await refresh;
    expect(await store.read(PreviewCredentialCache.key), isNull);
    await cache.close();
  });

  test(
    'a sign-out waits for an already-started write before erasing it',
    () async {
      final store = DelayedCredentialStore();
      final cache = PreviewCredentialCache(store);
      final refresh = cache.update(() async => 'fictional credential');
      await store.started.future;
      final clearing = cache.clear();
      store.finish.complete();
      await Future.wait([refresh, clearing]);
      expect(await store.read(PreviewCredentialCache.key), isNull);
      await cache.close();
    },
  );

  test(
    'newer accounts win and a failed load leaves no older credential',
    () async {
      final store = MemorySecretStore();
      final cache = PreviewCredentialCache(store);
      final old = Completer<String?>();
      final first = cache.update(() => old.future);
      await cache.update(() async => 'fictional newer credential');
      old.complete('fictional older credential');
      await first;
      expect(
        await store.read(PreviewCredentialCache.key),
        'fictional newer credential',
      );
      await expectLater(
        cache.update(() async => throw StateError('fictional load failure')),
        throwsStateError,
      );
      expect(await store.read(PreviewCredentialCache.key), isNull);
      await cache.close();
    },
  );

  test('mandatory preview revocation precedes Firebase sign-out', () async {
    final auth = MockFirebaseAuth(signedIn: true);
    var revoked = false;
    final service = AuthService(
      auth,
      FakeFirebaseFirestore(),
      beforeLocalSignOut: () async {
        expect(auth.currentUser, isNotNull);
        revoked = true;
      },
    );
    await service.signOut();
    expect(revoked, isTrue);
    expect(auth.currentUser, isNull);
  });

  test('failed preview revocation keeps the user signed in without exposing errors', () async {
    final auth = MockFirebaseAuth(signedIn: true);
    final service = AuthService(
      auth,
      FakeFirebaseFirestore(),
      beforeLocalSignOut: () async {
        throw StateError('fictional platform error');
      },
    );
    await expectLater(
      service.signOut(),
      throwsA(
        isA<AuthException>().having(
          (e) => e.message,
          'message',
          'Could not sign out. Try again.',
        ),
      ),
    );
    expect(auth.currentUser, isNotNull);
  });
}
