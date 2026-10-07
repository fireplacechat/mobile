import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/chat/message_limits.dart';
import 'package:fireplace/src/model/notifications/chat_activity.dart';
import 'package:fireplace/src/view/chat/message_actions.dart';
import 'package:fireplace/src/view/chat/message_menu.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

void main() {
  for (final (label, blocked, incoming, held, outgoing, status, body, expected)
      in [
        (
          'received',
          false,
          false,
          false,
          false,
          MessageStatus.ok,
          '**Hello**',
          ['copy', 'forward', 'selectText', 'report'],
        ),
        (
          'sent',
          false,
          false,
          false,
          true,
          MessageStatus.ok,
          'Hello',
          ['copy', 'forward', 'selectText'],
        ),
        (
          'blocked',
          true,
          false,
          false,
          false,
          MessageStatus.ok,
          'Hello',
          <String>[],
        ),
        (
          'incoming',
          false,
          true,
          false,
          false,
          MessageStatus.ok,
          'Hello',
          <String>[],
        ),
        (
          'identity hold',
          false,
          false,
          true,
          false,
          MessageStatus.ok,
          'Hello',
          <String>[],
        ),
        (
          'undecryptable',
          false,
          false,
          false,
          false,
          MessageStatus.undecryptable,
          'Hello',
          ['report'],
        ),
        (
          'unconfirmed',
          false,
          false,
          false,
          true,
          MessageStatus.unconfirmed,
          'Hello',
          ['copy', 'selectText'],
        ),
        (
          'oversized',
          false,
          false,
          false,
          false,
          MessageStatus.ok,
          'x' * (maxMessageCharacters + 1),
          ['copy', 'selectText', 'report'],
        ),
      ]) {
    testWidgets('message menu keeps exact $label action order and labels', (
      t,
    ) async {
      final f = UiFixture();
      addTearDown(f.session.close);
      List<MessageAction>? actions;
      await t.pumpWidget(
        ProviderScope(
          overrides: f.overrides,
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                actions = messageMenuActions(
                  message(
                    id: 'target',
                    body: body,
                    outgoing: outgoing,
                    status: status,
                  ),
                  ref: ref,
                  context: context,
                  isMounted: () => context.mounted,
                  notice: (_) {},
                  contactAction: (action) => action(),
                  chatId: () => 'alice_fred',
                  name: 'fred',
                  peerUid: 'fred',
                  blocked: blocked,
                  incomingRequest: incoming,
                  identityHeld: held,
                );
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(actions!.map((a) => a.id).toList(), expected);
      const labels = {
        'copy': 'Copy',
        'forward': 'Forward',
        'selectText': 'Select text',
        'report': 'Report',
      };
      expect(
        actions!.map((a) => a.label).toList(),
        expected.map((id) => labels[id]).toList(),
      );
    });
  }
  for (final unavailable in [false, true]) {
    testWidgets(
      'captured menu copy ${unavailable ? "after unmount is refused" : "copies plain text and gives feedback"}',
      (t) async {
        final f = UiFixture();
        await f.seed();
        addTearDown(f.session.close);
        var mounted = true;
        String? copied;
        final notices = <String>[];
        List<MessageAction>? actions;
        t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          },
        );
        addTearDown(
          () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await t.pumpWidget(
          ProviderScope(
            overrides: f.overrides,
            child: MaterialApp(
              home: Consumer(
                builder: (context, ref, _) {
                  ref.watch(appSessionProvider);
                  ref.watch(chatsProvider);
                  ref.watch(blockedUidsProvider);
                  ref.watch(hiddenChatsProvider);
                  ref.watch(identityAlertsProvider);
                  ref.watch(chatActivityProvider);
                  actions = messageMenuActions(
                    message(id: 'target', body: '**Hello**'),
                    ref: ref,
                    context: context,
                    isMounted: () => mounted,
                    notice: notices.add,
                    contactAction: (action) => action(),
                    chatId: () => 'alice_fred',
                    name: 'fred',
                    peerUid: 'fred',
                    blocked: false,
                    incomingRequest: false,
                    identityHeld: false,
                  );
                  return const SizedBox();
                },
              ),
            ),
          ),
        );
        await settleUi(t);
        mounted = !unavailable;
        actions!.first.onSelected();
        await settleUi(t);
        expect(copied, unavailable ? isNull : 'Hello');
        expect(notices, unavailable ? isEmpty : ['Message copied']);
      },
    );
  }
}
