import 'package:fireplace/src/model/chat/emoji_only.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'counts complete emoji, including joined ones, skin tones and flags',
    () {
      for (final emoji in [
        '🔥',
        '⭐',
        '✨',
        '❤️',
        '☺️',
        '✔️',
        '☝🏽',
        '👍🏿',
        '👨‍👩‍👧',
        '👩🏽‍💻',
        '❤️‍🔥',
        '🏳️‍🌈',
        '🇬🇧',
        '🏴󠁧󠁢󠁥󠁮󠁧󠁿',
        '1️⃣',
        '#⃣',
        '*️⃣',
      ]) {
        expect(emojiOnlyCount(emoji), 1, reason: emoji);
      }
      expect(emojiOnlyCount('👍🏾🇬🇧'), 2);
      expect(emojiOnlyCount('🎉🍎🔥'), 3);
    },
  );

  test('symbols shown as text are not emoji', () {
    for (final text in [
      '©',
      '®',
      '™',
      '‼',
      '★',
      '☆',
      '☺',
      '❤',
      '✔',
      '↔',
      'ℹ',
      '☀︎',
      '©©',
    ]) {
      expect(emojiOnlyCount(text), isNull, reason: text);
    }
  });

  test('any space, text or a fourth emoji keeps the bubble', () {
    for (final text in [
      '',
      ' ',
      '1',
      '#',
      '🔥 ',
      ' 🔥',
      '🔥\n',
      '👍 👍',
      '👍\n👍',
      '🔥!',
      'Hi 🔥',
      '👍́',
      '🇬',
      '🏽',
      '🔥' * 4,
      '🔥' * 5,
      '🔥${'́' * 16384}',
      ' ' * 16384,
    ]) {
      expect(
        emojiOnlyCount(text),
        isNull,
        reason: text.substring(0, text.length.clamp(0, 20)),
      );
    }
  });

  test('a message is trimmed for sending, except a space after emoji', () {
    expect(messageBodyToSend('  hello  '), 'hello');
    expect(messageBodyToSend('🔥'), '🔥');
    expect(messageBodyToSend(' 🔥'), '🔥');
    expect(messageBodyToSend('🔥 '), '🔥 ');
    expect(messageBodyToSend('🔥🔥  \n'), '🔥🔥 ');
    expect(messageBodyToSend('🔥 '), isNot(predicate(_bare)));
    expect(messageBodyToSend('Hi 🔥 '), 'Hi 🔥');
    expect(messageBodyToSend('🔥🔥🔥🔥 '), '🔥🔥🔥🔥');
    expect(messageBodyToSend('   '), '');
  });
}

bool _bare(Object? body) => emojiOnlyCount(body! as String) != null;
