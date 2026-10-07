import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('chat shows local message bubbles and a message composer', (
    t,
  ) async {
    final db = FakeFirebaseFirestore();
    final secrets = MemorySecretStore();
    final keys = KeyService(db, secrets);
    late final LocalDevice device;
    late final ChatService chat;
    late final MemoryMessageStore messages;
    late final SafetyService safety;

    await t.runAsync(() async {
      device = await keys.ensureDevice('alice');
      messages = MemoryMessageStore();
      safety = SafetyService(db, secrets, 'alice');
      chat = ChatService(
        db: db,
        uid: 'alice',
        device: device,
        keys: keys,
        prekeys: PreKeyService(db, secrets),
        safety: safety,
        secrets: secrets,
        messages: messages,
      );
      await messages.add(
        LocalMessage(
          id: 'message-1',
          chatId: 'alice_bob',
          senderUid: 'alice',
          senderDevice: device.keys.deviceId,
          outgoing: true,
          sentAt: DateTime(2026, 1, 2, 12),
          body: 'Hello from the hearth',
        ),
      );
    });
    final session = AppSession(
      uid: 'alice',
      username: 'alice',
      device: device,
      chat: chat,
      keys: keys,
      safety: safety,
      chatsSub: const Stream<void>.empty().listen((_) {}),
      dispose: () async {},
    );

    await t.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWithValue(const AsyncData(null)),
          appSessionProvider.overrideWithValue(AsyncData(session)),
          firestoreProvider.overrideWithValue(db),
        ],
        child: MaterialApp(
          theme: fireplaceTheme(Brightness.light),
          home: const ChatScreen(chatId: 'alice_bob'),
        ),
      ),
    );
    for (var i = 0; i < 25; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await t.pump();
    }

    expect(find.text('Hello from the hearth'), findsOneWidget);
    expect(find.byKey(const Key('composer')), findsOneWidget);
    expect(find.byKey(const Key('send')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.runAsync(() => safety.dispose());
  });
}
