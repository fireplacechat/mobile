// Review finding C01: formatMessage() is quadratic on deeply nested markers, so one crafted message
// (no size limit exists for message text) freezes every screen that formats it: bubbles, the chat-list
// preview, global search and the notice. The grammar must stay linear, or long text must skip it.
@Tags(['timing'])
library;

import 'package:fireplace/src/model/chat/message_format.dart';
import 'package:flutter_test/flutter_test.dart';

int ms(void Function() f) {
  final s = Stopwatch()..start();
  f();
  return s.elapsedMilliseconds;
}

void main() {
  for (final (name, open, close) in [
    ('italic', '_a ', 'a_ '),
    ('bold', '**a ', 'a** '),
    ('strike', '~~a ', 'a~~ '),
  ]) {
    test('nested $name markers: 48,000 characters format in under 250 ms', () {
      final n = 48000 ~/ (open.length + close.length);
      final s = open * n + close * n;
      expect(ms(() => formatMessage(s)), lessThan(250));
    });
  }
  test(
    'growth is not quadratic: 4x the input costs well under 8x the time',
    () {
      String make(int n) => '_a ' * n + 'a_ ' * n;
      formatMessage(make(500)); // warm up
      final small = ms(() => formatMessage(make(4000)));
      final large = ms(() => formatMessage(make(16000)));
      expect(large, lessThan((small < 5 ? 5 : small) * 8));
    },
  );
  test('ordinary long text is unaffected', () {
    final s = 'hello **world** and _more_ text ' * 3000;
    expect(ms(() => formatMessage(s)), lessThan(250));
  });
}
