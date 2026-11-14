import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fireplace/src/styles/chat_colors.dart';
import 'package:fireplace/src/styles/theme.dart';

// The highlight after a jump to a message must stand apart from both bubble
// colours and from the page, for every pair of chat colours (also the same
// colour twice) and in both modes.

List<double> _lab(Color c) {
  double lin(double u) =>
      u <= 0.04045 ? u / 12.92 : math.pow((u + 0.055) / 1.055, 2.4).toDouble();
  final r = lin(c.r), g = lin(c.g), b = lin(c.b);
  final x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047;
  final y = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  final z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883;
  double f(double t) =>
      t > 0.008856 ? math.pow(t, 1 / 3).toDouble() : 7.787 * t + 16 / 116;
  return [116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z))];
}

/// CIE76 colour difference: about 2 is just noticeable, 10 is clear.
double _difference(Color a, Color b) {
  final p = _lab(a), q = _lab(b);
  return math.sqrt(
    math.pow(p[0] - q[0], 2) +
        math.pow(p[1] - q[1], 2) +
        math.pow(p[2] - q[2], 2),
  );
}

void main() {
  for (final brightness in Brightness.values) {
    test('the jump highlight stands apart in ${brightness.name} mode', () {
      final page = fireplaceTheme(brightness).scaffoldBackgroundColor;
      for (final outgoing in ChatBubbleColor.values) {
        for (final incoming in ChatBubbleColor.values) {
          final pair = '${outgoing.label} & ${incoming.label}';
          final colors = ChatBubbleColors(outgoing: outgoing);
          final highlight = colors.jumpHighlight(
            brightness,
            page,
            other: incoming,
          );
          expect(highlight.a, 1, reason: pair);
          expect(
            _difference(highlight, outgoing.outgoing),
            greaterThan(9.5),
            reason: '$pair: too close to the outgoing bubble',
          );
          expect(
            _difference(highlight, incoming.incoming(brightness)),
            greaterThan(9.5),
            reason: '$pair: too close to the incoming bubble',
          );
          expect(
            _difference(highlight, page),
            greaterThan(9.5),
            reason: '$pair: too close to the page',
          );
        }
      }
    });
  }

  test('the highlight follows the chosen colours', () {
    final page = fireplaceTheme(Brightness.light).scaffoldBackgroundColor;
    const ember = ChatBubbleColors(outgoing: ChatBubbleColor.ember);
    const forest = ChatBubbleColors(outgoing: ChatBubbleColor.forest);
    expect(
      _difference(
        ember.jumpHighlight(
          Brightness.light,
          page,
          other: ChatBubbleColor.ember,
        ),
        forest.jumpHighlight(
          Brightness.light,
          page,
          other: ChatBubbleColor.forest,
        ),
      ),
      greaterThan(10),
    );
  });
}
