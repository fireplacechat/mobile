// Every speech bubble in the app is round (the owner's rule): the stock
// square ones must not come back. The round bubble lives in
// lib/src/widgets/round_bubble_icon.dart.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Square speech-bubble icons from the Material and Cupertino sets.
final _square = RegExp(
  r'\b(?:Icons\.(?:chat|chat_bubble|chat_bubble_outline|mark_chat_read|'
  r'mark_chat_unread|mark_unread_chat_alt|announcement|feedback|comment|'
  r'add_comment|mode_comment|insert_comment|comment_bank|comments_disabled|'
  r'forum|question_answer|sms|sms_failed|textsms|message|speaker_notes|'
  r'speaker_notes_off|rate_review|reviews|quickreply|maps_ugc|three_p|'
  r'contact_support|live_help|mms|voice_chat|try_sms_star|wechat)'
  r'(?:_outlined|_rounded|_sharp)?\b|'
  r'CupertinoIcons\.(?:bubble_left|bubble_right|bubble_middle_bottom|'
  r'bubble_middle_top|text_bubble|captions_bubble|exclamationmark_bubble|'
  r'ellipses_bubble|plus_bubble|quote_bubble|t_bubble|conversation_bubble|'
  r'bubble_left_bubble_right)(?:_fill)?\b)',
);

void main() {
  test('no square speech bubble icon anywhere in the app', () {
    final found = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final lines = file.readAsLinesSync();
      for (final (i, line) in lines.indexed) {
        for (final m in _square.allMatches(line)) {
          found.add('${file.path}:${i + 1} ${m.group(0)}');
        }
      }
    }
    expect(found, isEmpty, reason: 'Use roundBubble or RoundBubbleIcon.');
  });
}
