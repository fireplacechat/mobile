// The passphrase lock as the app drives it (decision 0033): turned on for the
// open session's account, locking closes the session before the key goes, and
// the right passphrase opens it again.
import 'package:fireplace/src/app/passphrase_lock_providers.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/db/secret_store.dart';
import 'package:fireplace/src/db/wrapping_secret_store.dart';
import 'package:fireplace/src/model/lock/passphrase_lock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/lock/passphrase_lock_test.dart' show fastDerive;
import '../support/ui_fixture.dart';

void main() {
  late MemorySecretStore inner;
  late WrappingSecretStore store;
  late ProviderContainer container;
  late UiFixture fixture;

  setUp(() {
    inner = MemorySecretStore()..data['identity:alice'] = 'secret';
    store = WrappingSecretStore(inner);
    fixture = UiFixture();
    container = ProviderContainer(
      overrides: [
        appSessionProvider.overrideWithValue(AsyncData(fixture.session)),
        secretStoreProvider.overrideWithValue(store),
        preferencesUidProvider.overrideWithValue('alice'),
        passphraseLockServiceProvider.overrideWithValue(
          PassphraseLock(
            store,
            derive: fastDerive,
            calibrate: () async => LockParameters.floor,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
  });

  PassphraseLockController controller() =>
      container.read(passphraseLockProvider.notifier);
  Future<PassphraseLockState> state() =>
      container.read(passphraseLockProvider.future);

  test('off until turned on; then on and open', () async {
    expect((await state()).on, isFalse);
    await controller().enable('correct horse');
    final s = await state();
    expect(s.on, isTrue);
    expect(s.locked, isFalse);
    expect(inner.data['identity:alice'], startsWith(wrappedSecretPrefix));
  });

  test(
    'Lock now closes the session, then nothing wrapped can be read',
    () async {
      await controller().enable('correct horse');
      await controller().lockNow();
      expect((await state()).locked, isTrue);
      await expectLater(
        store.read('identity:alice'),
        throwsA(isA<SecretsLocked>()),
      );
      expect(await controller().unlock('wrong one!'), isFalse);
      expect((await state()).locked, isTrue);
      expect(await controller().unlock('correct horse'), isTrue);
      expect((await state()).locked, isFalse);
      expect(await store.read('identity:alice'), 'secret');
    },
  );

  test('the auto-lock choice is kept; turning it off clears it all', () async {
    await controller().enable('correct horse');
    await controller().setAutoLock(AutoLock.oneHour);
    expect((await state()).autoLock, AutoLock.oneHour);
    await controller().disable();
    expect((await state()).on, isFalse);
    expect(inner.data['identity:alice'], 'secret');
  });
}
