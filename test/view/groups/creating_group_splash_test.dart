// The Creating splash of New group (issue 204): "Creating" and dots that
// count up and start again, still where motion is reduced.
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/groups/creating_group_splash.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> show(WidgetTester t, {bool reduceMotion = false}) =>
      t.pumpWidget(
        MaterialApp(
          theme: fireplaceTheme(Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: reduceMotion),
            child: child!,
          ),
          home: const CreatingGroupSplash(),
        ),
      );

  /// The visible words; the dots still to come are a clear span after them.
  String shown(WidgetTester t) =>
      (t.widget<Text>(find.byKey(const Key('creatingText'))).textSpan!
              as TextSpan)
          .text!;

  testWidgets('the dots go one, two, three, none and round again', (t) async {
    await show(t);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    final seen = [shown(t)];
    for (var i = 0; i < 4; i++) {
      await t.pump(CreatingDots.step);
      seen.add(shown(t));
    }
    expect(seen, [
      'Creating.',
      'Creating..',
      'Creating...',
      'Creating',
      'Creating.',
    ]);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('with reduced motion the dots stay still', (t) async {
    await show(t, reduceMotion: true);
    await t.pump(CreatingDots.step * 3);
    expect(shown(t), 'Creating...');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the splash cannot be left while the group is made', (t) async {
    await show(t);
    final pop = t.widget<PopScope>(find.byType(PopScope));
    expect(pop.canPop, isFalse);
    await t.pumpWidget(const SizedBox());
  });
}
