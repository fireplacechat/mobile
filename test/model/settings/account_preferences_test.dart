import 'dart:async';

import 'package:fireplace/src/db/account_erasure.dart';
import 'package:fireplace/src/db/secret_store.dart';
import 'package:fireplace/src/model/settings/account_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

class _HoldingStore extends MemorySecretStore {
  Completer<void>? started, release;
  @override
  Future<void> write(String key, String value) async {
    started?.complete();
    started = null;
    await release?.future;
    await super.write(key, value);
  }
}

void main() {
  test('legacy shared appearance is preserved for each local account before deleting one', () async {
    final store = MemorySecretStore()
      ..data.addAll({
        'identity:alice': 'alice',
        'identity:bob': 'bob',
        'ui:theme-mode': 'dark',
        'ui:chat-colors': 'ember|stone',
        'ui:send-sound': 'off',
      });
    final prefs = AccountPreferences(store);
    await prefs.deleting('alice');
    await eraseAccountSecrets(store, 'alice');
    for (final base in AccountPreferences.legacyKeys) {
      expect(store.data.containsKey(base), isFalse);
    }
    expect(await prefs.read('ui:theme-mode', null), isNull);
    expect(await prefs.read('ui:theme-mode', 'bob'), 'dark');
    expect(await prefs.read('ui:chat-colors', 'bob'), 'ember|stone');
    expect(await prefs.read('ui:send-sound', 'bob'), 'off');
    expect(store.data.keys.where((key) => key.endsWith(':alice')), isEmpty);
  });

  test('choices for two accounts persist independently', () async {
    final store = MemorySecretStore(), prefs = AccountPreferences(store);
    await prefs.write('ui:theme-mode', 'alice', 'light');
    await prefs.write('ui:theme-mode', 'bob', 'dark');
    final restarted = AccountPreferences(store);
    expect(await restarted.read('ui:theme-mode', 'alice'), 'light');
    expect(await restarted.read('ui:theme-mode', 'bob'), 'dark');
    expect(await restarted.read('ui:theme-mode', null), isNull);
  });

  test(
    'queued and late preference writes cannot resurrect an erased account',
    () async {
      final store = _HoldingStore()
        ..started = Completer<void>()
        ..release = Completer<void>();
      final started = store.started!.future;
      final prefs = AccountPreferences(store);
      final pending = prefs.write('ui:theme-mode', 'alice', 'dark');
      await started;
      final deleting = prefs.deleting('alice');
      store.release!.complete();
      await pending;
      await deleting;
      await eraseAccountSecrets(store, 'alice');
      await expectLater(
        prefs.write('ui:theme-mode', 'alice', 'light'),
        throwsStateError,
      );
      expect(store.data, isEmpty);
      await prefs.write('ui:theme-mode', 'bob', 'light');
      expect(await prefs.read('ui:theme-mode', 'bob'), 'light');
    },
  );
}
