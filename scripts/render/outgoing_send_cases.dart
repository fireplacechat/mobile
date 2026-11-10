import 'dart:async';

import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/app/chat_color_preference.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/support/ui_fixture.dart';
import 'catalog_case.dart';

final outgoingSendCases = <CatalogCase>[
  for (final state in [
    'sending-next',
    'queued',
    'failed',
    'failed-dialog',
    'failed-large',
    'failed-ocean',
  ])
    CatalogCase(
      'outgoing-$state',
      const ChatScreen(chatId: 'alice_fred'),
      size: state == 'failed-large'
          ? const Size(320, 640)
          : const Size(390, 844),
      textScale: state == 'failed-large' ? 2 : 1,
      prepare: (f) {
        if (state == 'failed-ocean') {
          f.secrets.data[ChatAppearance.storageKey] = 'ocean,stone';
        }
      },
      act: (t, f) async {
        final failed = state.startsWith('failed');
        if (failed) {
          f.chat.sendError = ChatException(
            'Nothing was sent. Try again later.',
          );
        } else {
          f.chat.sendHold = Completer<void>();
        }
        await t.enterText(
          find.byKey(const Key('composer')),
          'See you at two. I will bring dessert.',
        );
        await t.pump();
        await t.tap(find.byKey(const Key('send')));
        await settleUi(t);
        expect(
          t
              .widget<TextField>(find.byKey(const Key('composer')))
              .controller!
              .text,
          isEmpty,
        );
        expect(
          find.text(failed ? 'Not sent. Tap for options.' : 'Sending…'),
          failed ? findsOneWidget : findsNothing,
        );
        if (!failed) {
          expect(
            t
                .widget<Text>(
                  find.byKey(const ValueKey('sendState-outgoing-0')),
                )
                .data,
            '12:00 pm',
          );
        }
        if (state == 'sending-next' || state == 'queued') {
          await t.enterText(
            find.byKey(const Key('composer')),
            'Would you like anything else?',
          );
          await t.pump();
          expect(
            t.widget<IconButton>(find.byKey(const Key('send'))).onPressed,
            isNotNull,
          );
          if (state == 'queued') {
            await t.tap(find.byKey(const Key('send')));
            await settleUi(t);
            expect(find.text('Sending…'), findsNothing);
            expect(
              find.byKey(const ValueKey('sendState-outgoing-0')),
              findsOneWidget,
            );
            expect(
              find.byKey(const ValueKey('sendState-outgoing-1')),
              findsOneWidget,
            );
            expect(f.chat.sends, hasLength(1));
          }
        }
        if (state == 'failed-dialog') {
          await t.tap(find.text('Not sent. Tap for options.'));
          await t.pumpAndSettle();
        }
      },
    ),
];
