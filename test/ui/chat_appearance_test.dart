import 'package:fireplace/src/app/providers.dart';

import 'dart:math' as math;

import 'package:fireplace/fireplace_services.dart';

import 'package:fireplace/src/ui/chat_appearance.dart';
import 'package:fireplace/src/ui/chat_colors.dart';
import 'package:fireplace/src/ui/design_tokens.dart';
import 'package:fireplace/src/ui/presentation.dart';
import 'package:fireplace/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/ui_fixture.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (math.max(x, y) + .05) / (math.min(x, y) + .05);
}

void main() {
  test(
    'every selectable bubble color keeps normal text contrast in both themes',
    () {
      for (final brightness in Brightness.values) {
        final tokens = brightness == Brightness.light
            ? FireplaceUiTokens.light
            : FireplaceUiTokens.dark;
        for (final color in ChatBubbleColor.values) {
          expect(
            contrast(color.outgoing, tokens.outgoingText),
            greaterThanOrEqualTo(4.5),
            reason: '${color.name} outgoing',
          );
          expect(
            contrast(color.incoming(brightness), tokens.incomingText),
            greaterThanOrEqualTo(4.5),
            reason: '${color.name} incoming ${brightness.name}',
          );
        }
        expect(
          contrast(tokens.secondaryText, tokens.page),
          greaterThanOrEqualTo(4.5),
        );
      }
    },
  );

  testWidgets(
    'color choices update real bubbles, survive navigation, and reset explicitly',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authUserProvider.overrideWithValue(const AsyncData(null)),
          ],
          child: MaterialApp(
            theme: fireplaceTheme(Brightness.light),
            home: Builder(
              builder: (context) => Scaffold(
                body: Column(
                  children: [
                    MessageBubble(
                      message: message(
                        id: 'out',
                        body: 'An outgoing message',
                        outgoing: true,
                      ),
                    ),
                    MessageBubble(
                      message: message(id: 'in', body: 'An incoming message'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ChatAppearanceScreen(),
                        ),
                      ),
                      child: const Text('Choose colors'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      Color? bubble(String id) =>
          (tester
                      .widget<Container>(
                        find.byKey(ValueKey('messageBubble-$id')),
                      )
                      .decoration
                  as BoxDecoration)
              .color;
      expect(bubble('out'), ChatBubbleColor.ember.outgoing);
      await tester.tap(find.text('Choose colors'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('outgoing-ocean')),
        120,
      );
      await tester.tap(find.byKey(const Key('outgoing-ocean')));
      await tester.scrollUntilVisible(
        find.byKey(const Key('incoming-forest')),
        120,
      );
      await tester.tap(find.byKey(const Key('incoming-forest')));
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(bubble('out'), ChatBubbleColor.ocean.outgoing);
      expect(bubble('in'), ChatBubbleColor.forest.lightIncoming);
      await tester.tap(find.text('Choose colors'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Reset colors'), 120);
      await tester.tap(find.text('Reset colors'));
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(bubble('out'), ChatBubbleColor.ember.outgoing);
      expect(bubble('in'), ChatBubbleColor.stone.lightIncoming);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'a fresh app scope starts with defaults without a persistence dependency',
    () {
      final first = ProviderContainer(
        overrides: [authUserProvider.overrideWithValue(const AsyncData(null))],
      );
      first
          .read(chatBubbleColorsProvider.notifier)
          .outgoing(ChatBubbleColor.plum);
      first.dispose();
      final restarted = ProviderContainer(
        overrides: [authUserProvider.overrideWithValue(const AsyncData(null))],
      );
      addTearDown(restarted.dispose);
      expect(
        restarted.read(chatBubbleColorsProvider).outgoing,
        ChatBubbleColor.ember,
      );
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'color options and unreadable messages fit narrow large-text ${brightness.name}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authUserProvider.overrideWithValue(const AsyncData(null)),
            ],
            child: MaterialApp(
              theme: fireplaceTheme(brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: const ChatAppearanceScreen(),
            ),
          ),
        );
        await tester.pump();
        await tester.scrollUntilVisible(
          find.byKey(const Key('incoming-plum')),
          160,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('incoming-plum')));
        await tester.pump();
        expect(
          tester
              .widget<ChoiceChip>(find.byKey(const Key('incoming-plum')))
              .selected,
          isTrue,
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authUserProvider.overrideWithValue(const AsyncData(null)),
            ],
            child: MaterialApp(
              theme: fireplaceTheme(brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: Scaffold(
                body: ListView(
                  children: [
                    MessageBubble(
                      message: message(
                        id: 'bad',
                        body: 'Sent before this device was added.',
                        status: MessageStatus.undecryptable,
                      ),
                    ),
                    DaySeparator(date: fixtureTime),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
