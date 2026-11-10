// Chat colours are kept on the device, like the theme: a choice survives an
// app restart and signing out, and never leaves the phone.
import 'dart:async';

import 'package:fireplace/src/app/chat_color_preference.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/db/secret_store.dart';
import 'package:fireplace/src/styles/chat_colors.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/settings/chat_appearance.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _User extends Fake implements User {
  _User(this.uid);
  @override
  final String uid;
}

class FailingStore extends MemorySecretStore {
  bool failRead = false;
  bool failWrite = false;
  Completer<void>? holdRead;

  @override
  Future<String?> read(String key) async {
    await holdRead?.future;
    if (failRead) throw StateError('read failed');
    return super.read(key);
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWrite) throw StateError('write failed');
    await super.write(key, value);
  }
}

ProviderContainer containerFor(MemorySecretStore store, {Stream<User?>? auth}) {
  final container = ProviderContainer(
    overrides: [
      secretStoreProvider.overrideWithValue(store),
      if (auth != null) authUserProvider.overrideWith((ref) => auth),
    ],
  );
  addTearDown(container.dispose);
  container.listen(chatBubbleColorsProvider, (_, _) {});
  return container;
}

Future<ChatBubbleColors> loaded(ProviderContainer container) async {
  await container.read(chatBubbleColorsProvider.notifier).loaded;
  return container.read(chatBubbleColorsProvider);
}

void main() {
  test('a new install starts with the defaults', () async {
    expect(
      await loaded(containerFor(MemorySecretStore())),
      const ChatBubbleColors(),
    );
  });

  test('each choice survives an app restart', () async {
    final store = MemorySecretStore();
    final first = containerFor(store);
    await loaded(first);
    await first
        .read(chatBubbleColorsProvider.notifier)
        .outgoing(ChatBubbleColor.plum);
    await first
        .read(chatBubbleColorsProvider.notifier)
        .incoming(ChatBubbleColor.ocean);
    first.dispose();
    expect(
      await loaded(containerFor(store)),
      const ChatBubbleColors(
        outgoing: ChatBubbleColor.plum,
        incoming: ChatBubbleColor.ocean,
      ),
    );
    // Only the two names are written, under one key.
    expect(store.data, {ChatAppearance.storageKey: 'plum,ocean'});
  });

  test('reset is remembered too', () async {
    final store = MemorySecretStore()
      ..data[ChatAppearance.storageKey] = 'forest,plum';
    final container = containerFor(store);
    expect((await loaded(container)).outgoing, ChatBubbleColor.forest);
    await container.read(chatBubbleColorsProvider.notifier).reset();
    expect(await loaded(containerFor(store)), const ChatBubbleColors());
  });

  test('unknown or damaged saved values read as the defaults', () async {
    for (final (saved, expected) in [
      ('', const ChatBubbleColors()),
      ('teal,stone', const ChatBubbleColors()),
      ('ocean', const ChatBubbleColors(outgoing: ChatBubbleColor.ocean)),
      (
        'ocean,unknown,extra',
        const ChatBubbleColors(outgoing: ChatBubbleColor.ocean),
      ),
      (',forest', const ChatBubbleColors(incoming: ChatBubbleColor.forest)),
    ]) {
      final store = MemorySecretStore()
        ..data[ChatAppearance.storageKey] = saved;
      expect(await loaded(containerFor(store)), expected, reason: saved);
    }
  });

  test('an unreadable store falls back to the defaults', () async {
    final store = FailingStore()..failRead = true;
    expect(await loaded(containerFor(store)), const ChatBubbleColors());
  });

  test('a choice made while the saved one is loading wins', () async {
    final store = FailingStore()
      ..data[ChatAppearance.storageKey] = 'forest,plum'
      ..holdRead = Completer<void>();
    final container = containerFor(store);
    final saving = container
        .read(chatBubbleColorsProvider.notifier)
        .outgoing(ChatBubbleColor.ocean);
    store.holdRead!.complete();
    await saving;
    expect((await loaded(container)).outgoing, ChatBubbleColor.ocean);
  });

  test(
    'a failed save reports it, keeps the choice for now and permits retry',
    () async {
      final store = FailingStore();
      final container = containerFor(store);
      await loaded(container);
      final controller = container.read(chatBubbleColorsProvider.notifier);
      store.failWrite = true;
      await expectLater(
        controller.outgoing(ChatBubbleColor.plum),
        throwsStateError,
      );
      expect(
        container.read(chatBubbleColorsProvider).outgoing,
        ChatBubbleColor.plum,
      );
      expect(store.data, isEmpty);
      store.failWrite = false;
      await controller.outgoing(ChatBubbleColor.forest);
      expect(store.data[ChatAppearance.storageKey], 'forest,stone');
    },
  );

  test('signing out or switching account keeps the colours', () async {
    // They belong to the installation, as the theme does, and also colour
    // the signed-out screens.
    final auth = StreamController<User?>();
    addTearDown(auth.close);
    final container = containerFor(MemorySecretStore(), auth: auth.stream);
    container.listen(authUserProvider, (_, _) {});
    auth.add(_User('alice'));
    await loaded(container);
    await container
        .read(chatBubbleColorsProvider.notifier)
        .outgoing(ChatBubbleColor.plum);
    for (final next in [null, _User('bob')]) {
      auth.add(next);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(
        container.read(chatBubbleColorsProvider).outgoing,
        ChatBubbleColor.plum,
      );
    }
  });

  testWidgets('a failed save is explained in plain words', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = FailingStore()..failWrite = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [secretStoreProvider.overrideWithValue(store)],
        child: MaterialApp(
          theme: fireplaceTheme(Brightness.light),
          home: const ChatAppearanceScreen(),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('kept on this device'), findsOneWidget);
    expect(find.textContaining('reset when the app restarts'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('outgoing-ocean')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Could not save your colors. They will last until the app closes.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('StateError'), findsNothing);
    // The choice still shows.
    expect(
      tester
          .widget<ColorBlock>(find.byKey(const ValueKey('outgoing-ocean')))
          .selected,
      isTrue,
    );
  });
}
