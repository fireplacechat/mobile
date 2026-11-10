import 'package:flutter/material.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'catalog_case.dart';

final messageSurfaceCases = <CatalogCase>[
  for (final state in [
    'reaction-picker',
    'reaction-picker-large',
    'reaction-counts',
    'reaction-details',
    'remote-delete-confirmation',
    'remote-deleted',
  ])
    CatalogCase(
      'messages-$state',
      const ChatScreen(chatId: 'alice_fred'),
      size: state.endsWith('large')
          ? const Size(320, 640)
          : const Size(390, 844),
      textScale: state.endsWith('large') ? 2 : 1,
      act: (t, f) async {
        if (state.startsWith('remote')) {
          await t.longPress(find.byKey(const ValueKey('messageBubble-4')));
          await t.pumpAndSettle();
          await t.ensureVisible(
            find.byKey(const ValueKey('messageAction-deleteEveryone')),
          );
          await t.tap(
            find.byKey(const ValueKey('messageAction-deleteEveryone')),
          );
          await t.pumpAndSettle();
          if (state.endsWith('confirmation')) return;
          await t.ensureVisible(find.byKey(const Key('confirmRemoteDelete')));
          await t.tap(find.byKey(const Key('confirmRemoteDelete')));
          await t.pumpAndSettle();
          return;
        }
        if (state.contains('picker')) {
          await t.longPress(find.byKey(const ValueKey('messageBubble-5')));
          await t.pumpAndSettle();
          await t.ensureVisible(
            find.byKey(const ValueKey('messageAction-moreReactions')),
          );
          await t.tap(
            find.byKey(const ValueKey('messageAction-moreReactions')),
          );
          await t.pumpAndSettle();
          return;
        }
        await f.chat.react('alice_fred', '4', '👍');
        await f.chat.react('alice_fred', '5', '❤️');
        await t.pumpAndSettle();
        if (state.endsWith('details')) {
          await t.tap(find.byKey(const ValueKey('reaction-5-❤️')));
          await t.pumpAndSettle();
        }
      },
    ),
  for (final state in ['selected', 'delete-confirmation', 'deleted'])
    CatalogCase(
      'messages-$state',
      const ChatScreen(chatId: 'alice_fred'),
      act: (t, f) async {
        await t.longPress(find.byKey(const ValueKey('messageBubble-5')));
        await t.pumpAndSettle();
        await t.ensureVisible(
          find.byKey(const ValueKey('messageAction-select')),
        );
        await t.tap(find.byKey(const ValueKey('messageAction-select')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('messageBubble-4')));
        await t.pumpAndSettle();
        if (state == 'selected') return;
        await t.tap(find.byKey(const Key('deleteSelectedMessages')));
        await t.pumpAndSettle();
        if (state == 'delete-confirmation') return;
        await t.ensureVisible(find.byKey(const Key('confirmDeleteForMe')));
        await t.tap(find.byKey(const Key('confirmDeleteForMe')));
        await t.pumpAndSettle();
      },
    ),
];
