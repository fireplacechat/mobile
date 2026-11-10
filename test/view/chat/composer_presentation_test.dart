import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/src/styles/design_tokens.dart';

import '../../support/ui_fixture.dart';
import 'long_press_menu_test.dart' show openChat;

void main() {
  testWidgets(
    'rounded composer and circular send use the theme and preserve editing',
    (t) async {
      final f = UiFixture();
      await f.seed();
      addTearDown(f.session.close);
      await openChat(t, f);
      final input = find.byKey(const Key('composer'));
      await t.enterText(input, 'A message\nwith another line');
      await t.pump();
      final field = t.widget<TextField>(input);
      expect(field.decoration!.filled, isTrue);
      expect(
        (field.decoration!.enabledBorder as OutlineInputBorder).borderRadius,
        BorderRadius.circular(22),
      );
      final button = t.widget<IconButton>(find.byKey(const Key('send')));
      expect(button.style!.shape!.resolve({}), isA<CircleBorder>());
      expect(
        button.style!.backgroundColor!.resolve({}),
        FireplaceUiTokens.of(t.element(input)).accent,
      );
      await t.tap(find.byKey(const Key('send')));
      await t.pumpAndSettle();
      expect(f.chat.sends, ['A message\nwith another line']);
      expect(t.testTextInput.isVisible, isTrue);
    },
  );
}
