import 'package:fireplace/src/db/secret_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final calls = <MethodCall>[];
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test(
    'default secure store sends device-only unlocked options to iOS',
    () async {
      final store = SecureSecretStore();
      await store.write('fictional-key', 'fictional-value');
      await store.read('fictional-key');
      await store.delete('fictional-key');
      await store.clear();
      expect(calls.map((c) => c.method), [
        'write',
        'read',
        'delete',
        'deleteAll',
      ]);
      for (final call in calls) {
        final options = (call.arguments as Map)['options'] as Map;
        expect(options['accessibility'], 'unlocked_this_device');
        expect(options['synchronizable'], 'false');
      }
    },
  );
}
