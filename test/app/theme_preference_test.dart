import 'dart:async';

import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/app/theme_preference.dart';
import 'package:fireplace/src/db/secret_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FailingStore extends MemorySecretStore {
  bool failRead = false;
  bool failWrite = false;
  Completer<void>? hold;
  Completer<void>? started;

  @override
  Future<String?> read(String key) async {
    if (failRead) throw StateError('read failed');
    return super.read(key);
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWrite) throw StateError('write failed');
    if (started?.isCompleted == false) started!.complete();
    await hold?.future;
    await super.write(key, value);
  }
}

ProviderContainer containerFor(MemorySecretStore store) {
  final container = ProviderContainer(
    overrides: [secretStoreProvider.overrideWithValue(store)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('new installs and unknown saved values follow the system', () async {
    for (final saved in [null, 'unknown']) {
      final store = MemorySecretStore();
      if (saved != null) store.data[ThemePreference.storageKey] = saved;
      expect(
        await containerFor(store).read(themeModeProvider.future),
        ThemeMode.system,
      );
    }
  });

  test(
    'each choice survives recreation, including returning to system',
    () async {
      final store = MemorySecretStore();
      for (final mode in [ThemeMode.dark, ThemeMode.light, ThemeMode.system]) {
        final container = containerFor(store);
        await container.read(themeModeProvider.notifier).setMode(mode);
        expect(container.read(themeModeProvider).value, mode);
        expect(await containerFor(store).read(themeModeProvider.future), mode);
      }
    },
  );

  test('an unavailable store falls back to the device theme', () async {
    final store = FailingStore()..failRead = true;
    expect(
      await containerFor(store).read(themeModeProvider.future),
      ThemeMode.system,
    );
  });

  test('a failed save keeps the current choice and permits retry', () async {
    final store = FailingStore();
    final container = containerFor(store);
    final controller = container.read(themeModeProvider.notifier);
    await controller.setMode(ThemeMode.dark);
    store.failWrite = true;
    await expectLater(controller.setMode(ThemeMode.light), throwsStateError);
    expect(container.read(themeModeProvider).value, ThemeMode.dark);
    expect(
      await containerFor(store).read(themeModeProvider.future),
      ThemeMode.dark,
    );
    store.failWrite = false;
    await controller.setMode(ThemeMode.light);
    expect(container.read(themeModeProvider).value, ThemeMode.light);
  });

  test('queued choices are saved in order', () async {
    final store = FailingStore()..hold = Completer<void>();
    final container = containerFor(store);
    final controller = container.read(themeModeProvider.notifier);
    final dark = controller.setMode(ThemeMode.dark);
    final light = controller.setMode(ThemeMode.light);
    store.hold!.complete();
    await Future.wait([dark, light]);
    expect(
      await containerFor(store).read(themeModeProvider.future),
      ThemeMode.light,
    );
  });

  test('disposing during a save does not update disposed state', () async {
    final store = FailingStore()
      ..hold = Completer<void>()
      ..started = Completer<void>();
    final container = ProviderContainer(
      overrides: [secretStoreProvider.overrideWithValue(store)],
    );
    await container.read(themeModeProvider.future);
    final write = container
        .read(themeModeProvider.notifier)
        .setMode(ThemeMode.dark);
    await store.started!.future;
    container.dispose();
    store.hold!.complete();
    await write;
  });
}
