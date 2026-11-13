import 'package:fireplace/src/model/chat/message_selection.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'catalog_case.dart';

final selectionCopyCases = <CatalogCase>[
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS])
    for (final state in ['single', 'multiple', 'copied'])
      CatalogCase(
        'selection-toolbar-${platform.name.toLowerCase()}-$state',
        const ChatScreen(chatId: 'alice_fred'),
        platform: platform,
        size: platform == TargetPlatform.iOS
            ? const Size(375, 812)
            : const Size(360, 800),
        padding: platform == TargetPlatform.iOS
            ? const EdgeInsets.only(top: 44, bottom: 34)
            : const EdgeInsets.only(top: 24, bottom: 24),
        textScale: 1.35,
        pixelRatio: 3,
        act: (tester, fixture) async {
          final selection = ProviderScope.containerOf(
            tester.element(find.byType(ChatScreen)),
          ).read(messageSelectionProvider('alice_fred').notifier);
          selection.toggle('5');
          if (state != 'single') selection.toggle('4');
          await tester.pumpAndSettle();
          expect(
            Theme.of(
              tester.element(find.byKey(const Key('copySelectedMessages'))),
            ).platform,
            platform,
          );
          if (state == 'copied') {
            tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
              SystemChannels.platform,
              (call) async => null,
            );
            addTearDown(
              () => tester.binding.defaultBinaryMessenger
                  .setMockMethodCallHandler(SystemChannels.platform, null),
            );
            await tester.tap(find.byKey(const Key('copySelectedMessages')));
            await tester.pumpAndSettle();
          }
        },
      ),
];
