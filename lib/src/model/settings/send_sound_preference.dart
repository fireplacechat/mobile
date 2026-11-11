import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/notifications/system_notifications.dart';

final sendSoundProvider = AsyncNotifierProvider<SendSoundPreference, bool>(
  SendSoundPreference.new,
);

/// Whether sending a message plays the pop. On by default; belongs to this
/// installation, like the appearance setting.
class SendSoundPreference extends AsyncNotifier<bool> {
  static const storageKey = 'ui:send-sound';
  Future<void> _writes = Future.value();

  @override
  Future<bool> build() async {
    try {
      return await ref.watch(secretStoreProvider).read(storageKey) != 'off';
    } catch (_) {
      return true; // an unreadable preference must not silence the default
    }
  }

  Future<void> setOn(bool on) {
    final store = ref.read(secretStoreProvider);
    final write = _writes.then((_) async {
      if (!ref.mounted) return;
      await future;
      if (!ref.mounted) return;
      await store.write(storageKey, on ? 'on' : 'off');
      if (!ref.mounted) return;
      state = AsyncData(on);
    });
    // Serialize choices, and allow another choice after a failed save.
    _writes = write.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return write;
  }

  /// Plays the send pop unless it is turned off. The caller never waits and
  /// it never fails. The first send after launch waits for the saved choice,
  /// so "off" is honoured from the start.
  void play() => unawaited(_play());

  Future<void> _play() async {
    try {
      final on = state.hasValue ? state.value! : await future;
      if (!on || !ref.mounted) return;
      await ref.read(systemNotificationsProvider).playSendSound();
    } catch (_) {
      // A sound is never worth an error.
    }
  }
}
