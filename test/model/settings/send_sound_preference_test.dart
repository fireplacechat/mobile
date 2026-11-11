import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/db/secret_store.dart';
import 'package:fireplace/src/model/notifications/system_notifications.dart';
import 'package:fireplace/src/model/settings/send_sound_preference.dart';

class _System implements SystemNotifications {
  int played = 0;
  @override
  Future<void> setBadge(int count) async {}
  @override
  Future<void> clearDelivered() async {}
  @override
  Future<void> openSettings() async {}
  @override
  Future<void> playSendSound() async => played++;
}

class _BrokenStore extends MemorySecretStore {
  @override
  Future<String?> read(String key) => Future.error(StateError('locked'));
}

void main() {
  late _System system;
  ProviderContainer container(SecretStore store) {
    final c = ProviderContainer(
      overrides: [
        secretStoreProvider.overrideWithValue(store),
        systemNotificationsProvider.overrideWithValue(system),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() => system = _System());

  test('on by default, and sending plays the pop', () async {
    final c = container(MemorySecretStore());
    expect(await c.read(sendSoundProvider.future), isTrue);
    c.read(sendSoundProvider.notifier).play();
    await pumpEventQueue();
    expect(system.played, 1);
  });

  test('the first send after launch honours a saved "off"', () async {
    final store = MemorySecretStore()
      ..data[SendSoundPreference.storageKey] = 'off';
    final c = container(store);
    c.read(sendSoundProvider.notifier).play(); // before the choice has loaded
    await pumpEventQueue();
    expect(system.played, 0);
  });

  test('turning it off is saved and silences sending', () async {
    final store = MemorySecretStore();
    final c = container(store);
    await c.read(sendSoundProvider.future);
    await c.read(sendSoundProvider.notifier).setOn(false);
    c.read(sendSoundProvider.notifier).play();
    await pumpEventQueue();
    expect(system.played, 0);

    final again = container(store);
    expect(await again.read(sendSoundProvider.future), isFalse);
    await again.read(sendSoundProvider.notifier).setOn(true);
    again.read(sendSoundProvider.notifier).play();
    await pumpEventQueue();
    expect(system.played, 1);
  });

  test('an unreadable preference keeps the default', () async {
    final c = container(_BrokenStore());
    expect(await c.read(sendSoundProvider.future), isTrue);
  });
}
