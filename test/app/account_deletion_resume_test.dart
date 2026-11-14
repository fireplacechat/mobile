import 'dart:async';
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/app/theme_preference.dart';
import 'package:fireplace/src/app/chat_color_preference.dart';
import 'package:fireplace/src/db/secret_store.dart';
import 'package:fireplace/src/model/settings/account_preferences.dart';
import 'package:fireplace/src/model/settings/send_sound_preference.dart';
import 'package:fireplace/src/styles/chat_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _DisposedSession extends Fake implements AppSession {
  @override
  Future<void> close() async =>
      throw StateError('Session is already disposed.');
}

void main() {
  for (final loading in [false, true]) {
    test(
      'resume ignores a disposed session retained by ${loading ? 'loading' : 'error'} state',
      () async {
        final auth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
            uid: 'alice',
            email: 'alice@users.fireplace.invalid',
          ),
        );
        final db = FakeFirebaseFirestore(), store = MemorySecretStore();
        await db.doc('users/alice').set({
          'username': 'alice',
          'deleting': true,
        });
        store.data['identity:alice'] = 'fictional';
        final stale = _DisposedSession();
        var refreshing = false;
        final next = Completer<AppSession?>();
        final container = ProviderContainer(
          retry: (_, _) => null,
          overrides: [
            authProvider.overrideWithValue(auth),
            firestoreProvider.overrideWithValue(db),
            secretStoreProvider.overrideWithValue(store),
            iosPreviewCredentialsProvider.overrideWithValue(null),
            appSessionProvider.overrideWith(
              (_) => refreshing ? next.future : Future.value(stale),
            ),
            accountErasureDirectoriesProvider.overrideWithValue(() async => []),
          ],
        );
        addTearDown(container.dispose);
        container.listen(appSessionProvider, (_, _) {});
        await container.read(appSessionProvider.future);
        refreshing = true;
        container.invalidate(appSessionProvider);
        final refreshed = container.read(appSessionProvider.future);
        if (!loading) {
          next.completeError(AccountDeletionPending('alice'));
          await expectLater(refreshed, throwsA(isA<AccountDeletionPending>()));
        }
        await container.pump();
        expect(container.read(appSessionProvider).value, same(stale));
        await container
            .read(accountServiceProvider)
            .deleteAccount(password: 'fixture');
        expect(auth.currentUser, isNull);
        expect(store.data, isEmpty);
        if (loading) next.complete(null);
      },
    );
  }

  test('cold pending deletion erases account data and resets UI without opening a session', () async {
    final dir = await Directory.systemTemp.createTemp(
      'fireplace-resume-delete-',
    );
    addTearDown(() => dir.delete(recursive: true));
    for (final uid in ['alice', 'bob']) {
      await Directory('${dir.path}/messages_$uid').create();
      await File('${dir.path}/messages_$uid/chat-ui.enc')
          .writeAsString('encrypted $uid');
    }
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'alice', email: 'alice@users.fireplace.invalid'),
    );
    final db = FakeFirebaseFirestore();
    await db.doc('users/alice').set({'username': 'alice', 'deleting': true});
    await db.doc('usernames/alice').set({'uid': 'alice'});
    final colors = const ChatBubbleColors(outgoing: ChatBubbleColor.ocean);
    final store = MemorySecretStore()
      ..data.addAll({
        'identity:alice': 'fictional identity',
        'identity:bob': 'keep bob',
        'device:alice': '{"deviceId":"own-device"}',
        'sess:own-device:bob:peer': 'session',
        'ui:theme-mode': 'dark',
        'ui:chat-colors': colors.stored,
        'ui:send-sound': 'off',
      });
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWithValue(auth),
        firestoreProvider.overrideWithValue(db),
        secretStoreProvider.overrideWithValue(store),
        iosPreviewCredentialsProvider.overrideWithValue(null),
        appSessionProvider.overrideWith(
          (_) async => throw AccountDeletionPending('alice'),
        ),
        accountErasureDirectoriesProvider.overrideWithValue(() async => [dir]),
      ],
    );
    addTearDown(container.dispose);
    container.listen(themeModeProvider, (_, _) {});
    container.listen(chatBubbleColorsProvider, (_, _) {});
    container.listen(sendSoundProvider, (_, _) {});
    expect(await container.read(themeModeProvider.future), ThemeMode.dark);
    await container.read(chatBubbleColorsProvider.notifier).loaded;
    expect(container.read(chatBubbleColorsProvider), colors);
    expect(await container.read(sendSoundProvider.future), isFalse);
    await container
        .read(accountServiceProvider)
        .deleteAccount(password: 'fixture password');
    await container.pump();
    expect(auth.currentUser, isNull);
    expect(await container.read(themeModeProvider.future), ThemeMode.system);
    await container.read(chatBubbleColorsProvider.notifier).loaded;
    expect(container.read(chatBubbleColorsProvider), const ChatBubbleColors());
    expect(await container.read(sendSoundProvider.future), isTrue);
    expect(await Directory('${dir.path}/messages_alice').exists(), isFalse);
    expect(
      await File('${dir.path}/messages_bob/chat-ui.enc').readAsString(),
      'encrypted bob',
    );
    expect(store.data['identity:bob'], 'keep bob');
    expect(store.data[AccountPreferences.key('ui:theme-mode', 'bob')], 'dark');
    expect(
      store.data[AccountPreferences.key('ui:chat-colors', 'bob')],
      colors.stored,
    );
    expect(
      store.data.keys.any(
        (key) => key.contains('alice') || key.contains('own-device'),
      ),
      isFalse,
    );
  });
}
