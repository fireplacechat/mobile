import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';

import 'catalog_case.dart';

final replyEditCases = <CatalogCase>[
  for (final state in [
    'edit-composing',
    'edit-saved',
    'edit-history',
    'edit-large',
  ])
    CatalogCase(
      'messages-$state',
      const ChatScreen(chatId: 'alice_fred'),
      size: state.endsWith('large')
          ? const Size(320, 640)
          : const Size(390, 844),
      textScale: state.endsWith('large') ? 2 : 1,
      act: (t, f) async {
        await t.longPress(find.byKey(const ValueKey('messageBubble-4')));
        await t.pumpAndSettle();
        await t.ensureVisible(find.byKey(const ValueKey('messageAction-edit')));
        await t.tap(find.byKey(const ValueKey('messageAction-edit')));
        await t.pumpAndSettle();
        await t.enterText(
          find.byKey(const Key('composer')),
          'Looking forward to it. See you at three.',
        );
        await t.pump();
        if (state == 'edit-composing' || state == 'edit-large') return;
        await t.tap(find.byKey(const Key('send')));
        await t.pumpAndSettle();
        if (state == 'edit-history') {
          await t.tap(find.byKey(const ValueKey('edited-4')));
          await t.pump(const Duration(milliseconds: 350));
          await t.pumpAndSettle();
        }
      },
    ),
  for (final state in [
    'reply-composing',
    'reply-sent',
    'reply-original',
    'reply-large',
  ])
    CatalogCase(
      'messages-$state',
      const ChatScreen(chatId: 'alice_fred'),
      size: state.endsWith('large')
          ? const Size(320, 640)
          : const Size(390, 844),
      textScale: state.endsWith('large') ? 2 : 1,
      act: (t, f) async {
        await t.drag(
          find.byKey(const ValueKey('messageBubble-5')),
          const Offset(90, 0),
        );
        await t.pumpAndSettle();
        await t.enterText(
          find.byKey(const Key('composer')),
          'Two works for me.',
        );
        await t.pump();
        if (state == 'reply-composing' || state == 'reply-large') return;
        await t.tap(find.byKey(const Key('send')));
        await t.pumpAndSettle();
        if (state == 'reply-original') {
          await t.tap(find.byKey(const ValueKey('messageQuote-reply-1')));
          await t.pumpAndSettle();
        }
      },
    ),
];
