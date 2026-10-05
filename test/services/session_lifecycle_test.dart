import 'dart:async';
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/app/providers.dart';
// The existing path_provider plugin exposes its test seam through this interface.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class SessionUser extends Fake implements User {
  @override
  String get uid => 'fred';
  @override
  String get email => 'fred@users.fireplace.invalid';
}

class PausedStore extends MemorySecretStore {
  final entered = Completer<void>();
  final release = Completer<void>();
  int hiddenReads = 0;
  @override
  Future<String?> read(String key) async {
    if (key == 'chatprefskey:fred') {
      entered.complete();
      await release.future;
    }
    if (key == 'hidden:fred') hiddenReads++;
    return super.read(key);
  }
}

class SessionPaths extends PathProviderPlatform {
  SessionPaths(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'disposing an initializing session must prevent later subscriptions',
    () async {
      final dir = Directory.systemTemp.createTempSync('fp-session-lifecycle-');
      final originalPaths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = SessionPaths(dir.path);
      final db = FakeFirebaseFirestore();
      await db.doc('users/fred').set({'username': 'fred'});
      final secrets = PausedStore();
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          authUserProvider.overrideWith((_) => Stream.value(SessionUser())),
          firestoreProvider.overrideWithValue(db),
          secretStoreProvider.overrideWithValue(secrets),
        ],
      );
      container.listen(appSessionProvider, (_, _) {}, fireImmediately: true);
      try {
        unawaited(
          container
              .read(appSessionProvider.future)
              .then<void>(
                (_) {},
                onError: (Object error) {
                  if (!secrets.entered.isCompleted) {
                    secrets.entered.completeError(error);
                  }
                },
              ),
        );
        await secrets.entered.future.timeout(const Duration(seconds: 10));
        container.dispose();
        secrets.release.complete();
        await Future<void>.delayed(const Duration(milliseconds: 250));
        expect(
          secrets.hiddenReads,
          0,
          reason: 'a hidden-list read here proves the disposed session started reconciliation',
        );
      } finally {
        PathProviderPlatform.instance = originalPaths;
        dir.deleteSync(recursive: true);
      }
    },
  );
}
