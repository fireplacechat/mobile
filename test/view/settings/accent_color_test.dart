import 'dart:math' as math;

import 'package:fireplace/src/app.dart';
import 'package:fireplace/src/styles/chat_colors.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/auth/auth_screen.dart';
import 'package:fireplace/src/widgets/avatar.dart';
import 'package:fireplace/src/app/chat_color_preference.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (math.max(x, y) + .05) / (math.min(x, y) + .05);
}

void main() {
  test('the default theme is unchanged: ember is the accent', () {
    for (final brightness in Brightness.values) {
      final tokens = fireplaceTheme(brightness).extension<FireplaceUiTokens>()!;
      final base = brightness == Brightness.dark
          ? FireplaceUiTokens.dark
          : FireplaceUiTokens.light;
      expect(tokens.accent, base.accent);
      expect(tokens.accentText, base.accentText);
      expect(tokens.outgoingBubble, base.outgoingBubble);
    }
  });

  test('the chosen color becomes the primary color of the whole theme', () {
    for (final brightness in Brightness.values) {
      for (final color in ChatBubbleColor.values) {
        final theme = fireplaceTheme(brightness, accent: color);
        final tokens = theme.extension<FireplaceUiTokens>()!;
        expect(tokens.accent, color.outgoing);
        expect(tokens.outgoingBubble, color.outgoing);
        expect(theme.colorScheme.primary, color.outgoing);
        expect(theme.floatingActionButtonTheme.backgroundColor, color.outgoing);
        // The outline of a text box being typed in.
        expect(
          theme.inputDecorationTheme.focusedBorder!.borderSide.color,
          color.outgoing,
        );
        // Links and text buttons stay readable on the page and on panels.
        final text = tokens.accentText;
        expect(text, color.accentText(brightness));
        for (final surface in [tokens.page, tokens.panel]) {
          expect(
            contrast(text, surface),
            greaterThanOrEqualTo(4.5),
            reason: '${color.name} text ${brightness.name}',
          );
        }
        // White initials and icons on the fill.
        expect(contrast(Colors.white, color.outgoing), greaterThan(4.5));
      }
    }
  });

  testWidgets('choosing a color recolors the running app, avatars included', (
    tester,
  ) async {
    final fixture = UiFixture();
    await fixture.seed();
    addTearDown(fixture.session.close);
    await tester.pumpWidget(
      ProviderScope(overrides: fixture.overrides, child: const FireplaceApp()),
    );
    await tester.pumpAndSettle();
    final screen = tester.element(find.byType(AuthScreen));
    expect(FireplaceUiTokens.of(screen).accent, ChatBubbleColor.ember.outgoing);
    Navigator.of(screen).push<void>(
      MaterialPageRoute(
        builder: (_) => const Scaffold(body: PersonAvatar(name: 'Robin Vale')),
      ),
    );
    await tester.pumpAndSettle();
    ProviderScope.containerOf(tester.element(find.byType(PersonAvatar)))
        .read(chatBubbleColorsProvider.notifier)
        .outgoing(ChatBubbleColor.ocean);
    await tester.pumpAndSettle();
    final avatar = tester.element(find.byType(PersonAvatar));
    expect(FireplaceUiTokens.of(avatar).accent, ChatBubbleColor.ocean.outgoing);
    expect(
      Theme.of(avatar).colorScheme.primary,
      ChatBubbleColor.ocean.outgoing,
    );
    final fill =
        tester
                .widget<Container>(
                  find.descendant(
                    of: find.byType(PersonAvatar),
                    matching: find.byType(Container),
                  ),
                )
                .decoration!
            as BoxDecoration;
    expect(
      (fill.gradient! as LinearGradient).colors.last,
      ChatBubbleColor.ocean.outgoing,
    );
    // The color of received messages is not the accent.
    ProviderScope.containerOf(avatar)
        .read(chatBubbleColorsProvider.notifier)
        .incoming(ChatBubbleColor.plum);
    await tester.pumpAndSettle();
    expect(
      FireplaceUiTokens.of(tester.element(find.byType(PersonAvatar))).accent,
      ChatBubbleColor.ocean.outgoing,
    );
  });
}
