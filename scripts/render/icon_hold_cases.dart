// Review frames captured while a finger is still holding a real icon.
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'catalog_case.dart';

final iconHoldCases = <CatalogCase>[
  for (final control in ['verify', 'reaction', 'emoji-category'])
    CatalogCase(
      'icon-held-$control',
      const ChatScreen(chatId: 'alice_fred'),
      size: const Size(375, 812),
      padding: const EdgeInsets.only(top: 44, bottom: 34),
      pixelRatio: 3,
      act: (tester, fixture) async {
        final Finder target;
        if (control == 'verify') {
          target = find.byTooltip('Verify security code');
        } else {
          await tester.longPress(find.byKey(const ValueKey('messageBubble-5')));
          await tester.pumpAndSettle();
          if (control == 'reaction') {
            target = find.byTooltip('React with ❤️');
          } else {
            await tester.tap(find.byTooltip('More reactions'));
            await tester.pumpAndSettle();
            target = find.byTooltip('Smileys & People');
          }
        }
        final gesture = await tester.startGesture(tester.getCenter(target));
        addTearDown(gesture.cancel);
        await tester.pump(
          kLongPressTimeout + const Duration(milliseconds: 200),
        );
      },
    ),
];
