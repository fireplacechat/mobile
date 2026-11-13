import 'package:fireplace/src/db/secret_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const shared = MethodChannel('fireplace/preview_storage');
  final calls = <MethodCall>[];
  var preparations = 0;
  var failMigration = false;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    preparations = 0;
    failMigration = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(shared, (call) async {
          expect(call.method, 'prepare');
          preparations++;
          if (failMigration) throw PlatformException(code: 'shared_storage');
          return {
            'keychainGroup': 'TESTTEAMID.com.fireplacechat.app.shared',
            'directory': '/fictional-shared-container',
          };
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(preparations, greaterThan(0));
          calls.add(call);
          return null;
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(shared, null);
  });
  test('all iOS operations wait for migration and use the shared device-only group', () async {
    final store = SecureSecretStore();
    await store.write('fictional-key', 'fictional-value');
    await store.read('fictional-key');
    await store.delete('fictional-key');
    await store.clear();
    expect(preparations, 1);
    expect(calls.map((c) => c.method), [
      'write',
      'read',
      'delete',
      'deleteAll',
    ]);
    for (final call in calls) {
      final options = (call.arguments as Map)['options'] as Map;
      expect(options['accessibility'], 'first_unlock_this_device');
      expect(options['synchronizable'], 'false');
      expect(options['groupId'], 'TESTTEAMID.com.fireplacechat.app.shared');
    }
  });

  test(
    'migration failure never reads or writes an empty fallback store',
    () async {
      final store = SecureSecretStore();
      failMigration = true;
      await expectLater(
        store.read('fictional-key'),
        throwsA(isA<PlatformException>()),
      );
      await expectLater(
        store.write('fictional-key', 'fictional-value'),
        throwsA(isA<PlatformException>()),
      );
      await expectLater(
        store.delete('fictional-key'),
        throwsA(isA<PlatformException>()),
      );
      await expectLater(store.clear(), throwsA(isA<PlatformException>()));
      expect(calls, isEmpty);
      failMigration = false;
      await store.read('fictional-key');
      expect(calls.map((call) => call.method), ['read']);
    },
  );
}
