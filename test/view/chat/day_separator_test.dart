import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/view/chat/widgets/day_separator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const label = 'Tue, Nov 10';

  Future<void> pump(
    WidgetTester tester, {
    required double width,
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: fireplaceTheme(Brightness.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: DaySeparator(date: DateTime(2026, 11, 10)),
            ),
          ),
        ),
      ),
    );
  }

  double paintedScale(WidgetTester tester) {
    final fitted = tester.renderObject<RenderFittedBox>(find.byType(FittedBox));
    return fitted.size.width / fitted.child!.size.width;
  }

  testWidgets('a date stays on one line and shrinks only when it must', (
    tester,
  ) async {
    await pump(tester, width: 400);
    expect(find.text(label), findsOneWidget);
    expect(tester.widget<Text>(find.text(label)).maxLines, 1);
    expect(paintedScale(tester), closeTo(1, 0.01));
    expect(
      tester.renderObject<RenderParagraph>(find.text(label)).size.height,
      lessThan(24),
    );
    for (final line in tester.renderObjectList<RenderBox>(
      find.byType(Divider),
    )) {
      expect(line.size.width, greaterThan(12));
    }

    await pump(tester, width: 288);
    expect(tester.takeException(), isNull);
    expect(find.text(label), findsOneWidget);
    expect(paintedScale(tester), closeTo(1, 0.01));
    expect(
      tester.renderObject<RenderParagraph>(find.text(label)).size.height,
      lessThan(24),
    );

    await pump(tester, width: 80);
    expect(tester.takeException(), isNull);
    expect(find.text(label), findsOneWidget);
    expect(paintedScale(tester), lessThan(0.8));
    expect(
      tester.renderObject<RenderFittedBox>(find.byType(FittedBox)).size.width,
      lessThanOrEqualTo(80 - 24),
    );
    for (final line in tester.renderObjectList<RenderBox>(
      find.byType(Divider),
    )) {
      expect(line.size.width, greaterThanOrEqualTo(12));
    }

    await pump(tester, width: 160, scale: 2);
    expect(tester.takeException(), isNull);
    expect(find.text(label), findsOneWidget);
    expect(paintedScale(tester), lessThan(1));
    expect(
      tester.renderObject<RenderParagraph>(find.text(label)).size.height,
      lessThan(40),
    );
  });
}
