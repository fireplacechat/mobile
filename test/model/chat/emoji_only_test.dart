import 'package:fireplace/src/model/chat/emoji_only.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('counts complete emoji graphemes, including modifiers and keycaps', () {
    for (final emoji in [
      '🔥',
      '👨‍👩‍👧',
      '👩🏽‍💻',
      '👍🏿',
      '🇬🇧',
      '1️⃣',
      '#⃣',
      '*️⃣',
    ]) {
      expect(emojiOnlyCount(emoji), 1, reason: emoji);
    }
    expect(emojiOnlyCount(' \n👍🏾🇬🇧\t'), 2);
    expect(emojiOnlyCount('🎉🍎🔥'), 3);
  });

  test('regular messages, text presentation and excess emoji keep bubbles', () {
    for (final text in [
      '',
      ' ',
      '1',
      '#',
      '🔥!',
      'Hi 🔥',
      '👍 ok',
      '👍 👍',
      '👍\n👍',
      '👍\u0301',
      '☀\uFE0E',
      '🇬',
      '🏽',
      '🔥' * 4,
      '🔥' * 5,
      '🔥${'\u0301' * 16384}',
      ' ' * 16384,
    ]) {
      expect(
        emojiOnlyCount(text),
        isNull,
        reason: text.substring(0, text.length.clamp(0, 20)),
      );
    }
  });
}
