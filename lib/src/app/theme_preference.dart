import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/providers.dart';

final themeModeProvider = AsyncNotifierProvider<ThemePreference, ThemeMode>(
  ThemePreference.new,
);

/// Appearance belongs to this installation, including the signed-out screens.
class ThemePreference extends AsyncNotifier<ThemeMode> {
  static const storageKey = 'ui:theme-mode';
  Future<void> _writes = Future.value();

  @override
  Future<ThemeMode> build() async {
    final store = ref.watch(secretStoreProvider);
    try {
      final saved = await store.read(storageKey);
      return switch (saved) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    } catch (_) {
      // An unavailable appearance preference must not prevent opening the app.
      return ThemeMode.system;
    }
  }

  Future<void> setMode(ThemeMode mode) {
    final store = ref.read(secretStoreProvider);
    final write = _writes.then((_) async {
      if (!ref.mounted) return;
      await future;
      if (!ref.mounted) return;
      await store.write(storageKey, mode.name);
      if (!ref.mounted) return;
      state = AsyncData(mode);
    });
    // Serialize choices, and allow another choice after a failed save.
    _writes = write.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return write;
  }
}
