// Review finding E2: the keyboard focus ring is drawn as part of the bubble border, so focusing a message
// makes it 4 px wider and taller and shifts its text (a visible jump while tabbing through a chat).
// The ring must be painted over the bubble without changing its size.
import 'package:fireplace/src/ui/chat_screen.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

bool isBubble(Widget w) =>
    w.key is ValueKey &&
    '${(w.key as ValueKey).value}'.startsWith('messageBubble-');

void main() {
  testWidgets('focusing a message bubble does not change its size', (t) async {
    final f = UiFixture();
    await f.seed();
    addTearDown(f.session.close);
    await t.pumpWidget(
      ProviderScope(
        overrides: f.overrides,
        child: MaterialApp(
          theme: fireplaceTheme(Brightness.light),
          home: const ChatScreen(chatId: 'alice_fred'),
        ),
      ),
    );
    await settleUi(t);
    final bubbles = find.byWidgetPredicate(isBubble);
    final before = {
      for (final e in bubbles.evaluate())
        (e.widget.key! as ValueKey).value: t.getSize(find.byWidget(e.widget)),
    };
    expect(before, isNotEmpty);
    var checked = 0;
    for (var i = 0; i < 40; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      final ctx = FocusManager.instance.primaryFocus?.context;
      if (ctx == null) continue;
      final inside = find.descendant(
        of: find.byWidget(ctx.widget),
        matching: find.byWidgetPredicate(isBubble),
      );
      if (inside.evaluate().isEmpty) continue;
      final key = (inside.evaluate().single.widget.key! as ValueKey).value;
      expect(
        t.getSize(inside),
        before[key],
        reason: 'bubble $key changed size while focused',
      );
      checked++;
    }
    expect(
      checked,
      greaterThan(0),
      reason: 'Tab never reached a message bubble',
    );
  });
}
