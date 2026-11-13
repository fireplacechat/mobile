import 'package:fireplace/src/app/chat_color_preference.dart';
import 'package:fireplace/src/view/settings/settings_screen.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../scripts/render/render_screens_test.dart' show loadFonts;
import '../../support/ui_fixture.dart';

Future<void> _openSettings(
  WidgetTester t, {
  Size size = const Size(800, 3000),
  double textScale = 1,
  String? savedColors,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final f = UiFixture();
  if (savedColors != null) {
    f.secrets.data[ChatAppearance.storageKey] = savedColors;
  }
  addTearDown(f.session.close);
  await t.pumpWidget(
    ProviderScope(
      overrides: f.overrides,
      child: MaterialApp(
        theme: fireplaceTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const SettingsScreen(),
      ),
    ),
  );
  await settleUi(t);
}

Finder _inTile(String key, Finder matching) =>
    find.descendant(of: find.byKey(Key(key)), matching: matching);

void main() {
  // Real glyph widths: the test font draws every letter as a square.
  setUpAll(loadFonts);
  testWidgets('Chat colors names your colour, then theirs', (t) async {
    await _openSettings(t);
    expect(_inTile('chatColors', find.text('Ember & Stone')), findsOneWidget);

    await _openSettings(t, savedColors: 'ember,plum');
    expect(_inTile('chatColors', find.text('Ember & Plum')), findsOneWidget);
    expect(find.text('Choose your bubble colors'), findsNothing);
  });

  for (final scale in [1.0, 1.35]) {
    testWidgets('the longest pair fits on one line on a narrow phone '
        '(text size $scale)', (t) async {
      await _openSettings(
        t,
        size: const Size(320, 3000),
        textScale: scale,
        savedColors: 'forest,forest',
      );
      final text = _inTile('chatColors', find.text('Forest & Forest'));
      expect(text, findsOneWidget);
      final widget = t.widget<Text>(text);
      final painter = TextPainter(
        text: TextSpan(
          text: widget.data,
          style: DefaultTextStyle.of(t.element(text)).style.merge(widget.style),
        ),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.linear(scale),
      )..layout();
      addTearDown(painter.dispose);
      expect(
        t.getSize(text).height,
        moreOrLessEquals(painter.height, epsilon: .5),
        reason: 'one line high',
      );
    });
  }

  testWidgets('the account and about rows are plain buttons', (t) async {
    await _openSettings(t);
    for (final (key, title) in [
      ('recoveryKey', 'Recovery key'),
      ('deleteAccountTile', 'Delete account'),
      ('signOut', 'Sign out'),
      ('openPrivacyPolicy', 'Privacy policy'),
      ('openTermsOfUse', 'Terms of use'),
    ]) {
      final tile = t.widget<ListTile>(find.byKey(Key(key)));
      expect((tile.title! as Text).data, title);
      expect(tile.subtitle, isNull, reason: '$title has no second line');
    }
  });
}
