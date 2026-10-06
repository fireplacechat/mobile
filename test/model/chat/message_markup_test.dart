import 'package:fireplace/src/model/chat/message_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (raw, plain) in [
    ('**bold**', 'bold'),
    ('_italic_', 'italic'),
    ('~~gone~~', 'gone'),
    ('_hello **there**_', 'hello there'),
    ('**bold _inside_**', 'bold inside'),
    ('_bold **inside** too_', 'bold inside too'),
    (
      'snake_case some_file_name @jo_smith',
      'snake_case some_file_name @jo_smith',
    ),
    ('a_b_c a__b __name__', 'a_b_c a__b __name__'),
    ('unmatched **bold _italics', 'unmatched **bold _italics'),
    (r'\*\*literal\*\* \_word\_ \~~gone\~~', '**literal** _word_ ~~gone~~'),
    ('Hello (_world_)!', 'Hello (world)!'),
    ('**emoji 👨‍👩‍👧‍👦 ☕** _café_', 'emoji 👨‍👩‍👧‍👦 ☕ café'),
    ('@éva_test café_crème', '@éva_test café_crème'),
    ('_hello_—_there_。', 'hello—there。'),
    ('字_word_𐐀', '字_word_𐐀'),
    ('** ** _ _ ~~ ~~', '** ** _ _ ~~ ~~'),
    (
      '<b>text</b> https://example.invalid',
      '<b>text</b> https://example.invalid',
    ),
  ]) {
    test(
      'literal/edge grammar: $raw',
      () => expect(formatMessage(raw).plain, plain),
    );
  }
  test('nested styles stay nested and terminate', () {
    final runs = formatMessage('_one **two ~~three~~** four_ plain').runs;
    expect(runs.where((r) => r.text == 'three').single.bold, isTrue);
    expect(runs.where((r) => r.text == 'three').single.italic, isTrue);
    expect(runs.where((r) => r.text == 'three').single.strike, isTrue);
    expect(runs.last.italic, isFalse);
  });
  test('hostile markers and large UTF-8 messages do not recurse', () {
    final text = '${'_' * 50000} ${'😀 **hello** ' * 5000}';
    final parsed = formatMessage(text);
    expect(parsed.plain, contains('😀 hello'));
    expect(parsed.plain, startsWith('_' * 50000));
  });
  test('unclosed parent still leaves its markers literal', () {
    expect(formatMessage('_one **two**').plain, '_one two');
  });
}
