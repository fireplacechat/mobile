import 'package:characters/characters.dart';

// One emoji, as a phone shows it: a picture shown as an emoji by default, or
// one asked to be an emoji (U+FE0F) or given a skin tone, then any pictures
// joined to it (U+200D) and a subdivision tag; a flag; or a keycap. Symbols
// shown as text by default (©, ®, ™, ‼, ★) are not emoji, and neither is a
// skin tone or half a flag on its own.
const _first =
    r'(?:(?![\p{Regional_Indicator}\p{Emoji_Modifier}])'
    r'\p{Emoji_Presentation}️?\p{Emoji_Modifier}?'
    r'|\p{Extended_Pictographic}(?:️\p{Emoji_Modifier}?|\p{Emoji_Modifier}))';
const _joined = r'(?:‍\p{Extended_Pictographic}️?\p{Emoji_Modifier}?)*';
const _tags = '(?:[\u{E0020}-\u{E007E}]+\u{E007F})?';
final _emoji = RegExp(
  // The analyzer's regex check does not know these Unicode property escapes;
  // the runtime does (emoji_only_test).
  // ignore: valid_regexps
  '^(?:\\p{Regional_Indicator}{2}|[0-9#*]\\uFE0F?\\u20E3|$_first$_joined$_tags)\$',
  unicode: true,
);

/// One to three emoji and nothing else, not even a space: the message shows
/// them large, without a bubble (issue 247). Null for anything else. The
/// length check comes first: one grapheme can hold thousands of marks.
int? emojiOnlyCount(String text) {
  if (text.isEmpty || text.length > 64) return null;
  var count = 0;
  for (final cluster in text.characters) {
    if (++count > 3 || !_emoji.hasMatch(cluster)) return null;
  }
  return count;
}

/// The text a message is sent or saved with: trimmed, as always, except that
/// a space typed after emoji is kept, so they stay in a bubble on both phones
/// (the owner's rule for issue 247).
String messageBodyToSend(String draft) {
  final body = draft.trim();
  final spaceAfter = body.length < draft.trimLeft().length;
  return spaceAfter && emojiOnlyCount(body) != null ? '$body ' : body;
}
