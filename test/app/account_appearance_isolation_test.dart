import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/app/theme_preference.dart';
import 'package:fireplace/src/app/chat_color_preference.dart';
import 'package:fireplace/src/db/secret_store.dart';
import 'package:fireplace/src/model/settings/send_sound_preference.dart';
import 'package:fireplace/src/styles/chat_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _User extends Fake implements User {
  _User(this.uid);
  @override
  final String uid;
}

class _Auth extends Fake implements FirebaseAuth {
  User? user = _User('alice');
  final changes = StreamController<User?>.broadcast();
  @override
  User? get currentUser => user;
  @override
  Stream<User?> authStateChanges() async* {
    yield user;
    yield* changes.stream;
  }

  void select(String uid) {
    user = _User(uid);
    changes.add(user);
  }
}

void main() {
  test(
    'theme, chat colours and sound follow their account across switches',
    () async {
      final auth = _Auth(), store = MemorySecretStore();
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWithValue(auth),
          secretStoreProvider.overrideWithValue(store),
          iosPreviewCredentialsProvider.overrideWithValue(null),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await auth.changes.close();
      });
      container.listen(themeModeProvider, (_, _) {});
      container.listen(chatBubbleColorsProvider, (_, _) {});
      container.listen(sendSoundProvider, (_, _) {});
      await container.read(themeModeProvider.future);
      await container.read(themeModeProvider.notifier).setMode(ThemeMode.dark);
      await container
          .read(chatBubbleColorsProvider.notifier)
          .outgoing(ChatBubbleColor.ocean);
      await container.read(sendSoundProvider.notifier).setOn(false);
      auth.select('bob');
      await container.pump();
      expect(await container.read(themeModeProvider.future), ThemeMode.system);
      await container.read(chatBubbleColorsProvider.notifier).loaded;
      expect(
        container.read(chatBubbleColorsProvider),
        const ChatBubbleColors(),
      );
      expect(await container.read(sendSoundProvider.future), isTrue);
      await container.read(themeModeProvider.notifier).setMode(ThemeMode.light);
      await container
          .read(chatBubbleColorsProvider.notifier)
          .outgoing(ChatBubbleColor.forest);
      auth.select('alice');
      await container.pump();
      expect(await container.read(themeModeProvider.future), ThemeMode.dark);
      await container.read(chatBubbleColorsProvider.notifier).loaded;
      expect(
        container.read(chatBubbleColorsProvider).outgoing,
        ChatBubbleColor.ocean,
      );
      expect(await container.read(sendSoundProvider.future), isFalse);
      auth.select('bob');
      await container.pump();
      expect(await container.read(themeModeProvider.future), ThemeMode.light);
      await container.read(chatBubbleColorsProvider.notifier).loaded;
      expect(
        container.read(chatBubbleColorsProvider).outgoing,
        ChatBubbleColor.forest,
      );
      expect(await container.read(sendSoundProvider.future), isTrue);
    },
  );
}
