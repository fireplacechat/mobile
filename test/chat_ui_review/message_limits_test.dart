import 'package:fireplace/src/services/message_limits.dart';
import 'package:fireplace/src/ui/message_input_formatter.dart';
import 'package:fireplace/src/ui/message_format.dart';
import 'package:fireplace/src/ui/chat_activity.dart';

import '../support/ui_fixture.dart';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final char in ['x', '🙂', '𐐀']) {
    test('exact boundary and one over for $char', () {
      final text = char * maxMessageCharacters;
      expect(messageCharacters(text), maxMessageCharacters);
      expect(messageTooLong(text), isFalse);
      expect(messageTooLong('$text$char'), isTrue);
      final input = MessageInputFormatter().formatEditUpdate(
        TextEditingValue.empty,
        TextEditingValue(
          text: '$text$char',
          selection: TextSelection.collapsed(offset: text.length + char.length),
        ),
      );
      expect(input.text, text);
      expect(input.selection.extentOffset, text.length);
    });
  }
  test('combining marks and ZWJ parts count as separate code points', () {
    expect(messageCharacters('e\u0301'), 2);
    expect(messageCharacters('👨‍👩‍👦'), 5);
    final text = '${'a' * (maxMessageCharacters - 2)}e\u0301';
    expect(messageTooLong(text), isFalse);
    expect(messageTooLong('$text\u0301'), isTrue);
    final clipped = MessageInputFormatter().formatEditUpdate(
      TextEditingValue.empty,
      TextEditingValue(text: '$text\u0301'),
    );
    expect(clipped.text, text);
  });
  test('inserting or pasting at the cap preserves the existing suffix', () {
    final old = '${'a' * (maxMessageCharacters - 1)}Z';
    final next = 'Q$old';
    final result = MessageInputFormatter().formatEditUpdate(
      TextEditingValue(
        text: old,
        selection: const TextSelection.collapsed(offset: 0),
      ),
      TextEditingValue(
        text: next,
        selection: const TextSelection.collapsed(offset: 1),
      ),
    );
    expect(result.text, old);
    expect(result.selection.extentOffset, 0);
    final below = '${'a' * (maxMessageCharacters - 2)}Z';
    final pasted = MessageInputFormatter().formatEditUpdate(
      TextEditingValue(text: below),
      TextEditingValue(
        text: '🙂🙂$below',
        selection: const TextSelection.collapsed(offset: 4),
      ),
    );
    expect(pasted.text, '🙂$below');
    expect(pasted.selection.extentOffset, 2);
  });
  test('composing ranges cannot point into removed Unicode characters', () {
    final text = '${'🙂' * maxMessageCharacters}e\u0301';
    final result = MessageInputFormatter().formatEditUpdate(
      TextEditingValue.empty,
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
        composing: TextRange(start: text.length - 2, end: text.length),
      ),
    );
    expect(result.composing, TextRange.empty);
    expect(result.selection.extentOffset, maxMessageCharacters * 2);
  });
  test('hostile oversized text bypasses formatting and keeps all literals', () {
    final body = '**bold** \\_literal_ ${'_a ' * 10000}${'a_ ' * 10000}';
    final displayed = displayMessage(body);
    expect(displayed.plain, body);
    expect(displayed.runs, hasLength(1));
    expect(displayed.runs.single.bold, isFalse);
    expect(displayed.runs.single.italic, isFalse);
    expect(
      messageCharacters(messagePreview(body)),
      oversizedPreviewCharacters + 1,
    );
    expect(messagePreview(body), startsWith('**bold** \\_literal_'));
  });
  test('oversized search keeps literal markers and escapes', () {
    final raw = '**literal** \\_token_ ${'x' * (maxMessageCharacters + 1)}';
    final hits = searchMessages({
      'alice_fred': [message(id: 'oversized-search', body: raw)],
    }, '**literal**');
    expect(hits, hasLength(1));
    expect(hits.single.text, raw);
    expect(hits.single.start, 0);
    expect(hits.single.end, '**literal**'.length);
  });
  test('ordinary backslash handling and formatted Copy stay unchanged', () {
    expect(
      displayMessage(r'**bold** \_literal\_ \\ \*').plain,
      r'bold _literal_ \ *',
    );
  });
}
