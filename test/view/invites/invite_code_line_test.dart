// An invite code is always on one line: on a narrow phone, or with large
// text, it is drawn smaller instead of breaking at its hyphens.
import 'package:fireplace/src/model/invites/invite_rows.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/invites/invite_ticket.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 11, 15);
  // Wide letters: the worst case for width.
  const code = 'WWWWMMMMWWWWMMMM';

  for (final (width, scale) in [(320.0, 1.0), (390.0, 1.0), (390.0, 2.0)]) {
    testWidgets('one line at $width wide, text scale $scale', (t) async {
      t.view.physicalSize = Size(width, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          theme: fireplaceTheme(Brightness.dark),
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 800),
              textScaler: TextScaler.linear(scale),
            ),
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(20),
                child: InviteTicket(
                  row: CodeInvite(
                    0,
                    const InviteSlot(code: code, invite: 'x'),
                    replaceAfter: now,
                  ),
                  now: now,
                  busy: false,
                  onCreate: () {},
                  onCopy: () {},
                  onReplace: () {},
                ),
              ),
            ),
          ),
        ),
      );
      final text = find.byKey(const Key('inviteCode0'));
      expect(find.text('WWWW-MMMM-WWWW-MMMM'), findsOneWidget);
      final paragraph = t.renderObject<RenderParagraph>(text);
      final lines = paragraph.getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: 19),
      );
      expect(lines.map((b) => b.top).toSet().length, 1);
      // Inside the card, not cut off.
      final card = t.getRect(find.byKey(const Key('inviteTicket0')));
      final drawn = t.getRect(text);
      expect(drawn.left, greaterThanOrEqualTo(card.left));
      expect(drawn.right, lessThanOrEqualTo(card.right));
      expect(t.takeException(), isNull);
    });
  }
}
