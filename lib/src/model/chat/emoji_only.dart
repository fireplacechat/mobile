// Flutter supplies characters; import it directly to keep widgets out of the model.
// ignore: depend_on_referenced_packages
import 'package:characters/characters.dart';

final _emoji = RegExp(
  // The analyzer's legacy regex parser rejects these Unicode property escapes.
  // ignore: valid_regexps
  r'^(?:\p{Regional_Indicator}{2}|[0-9#*]\uFE0F?\u20E3|'
  r'\p{Extended_Pictographic}\uFE0F?\p{Emoji_Modifier}?'
  r'(?:\u200D\p{Extended_Pictographic}\uFE0F?\p{Emoji_Modifier}?)*'
  '(?:[\u{E0020}-\u{E007E}]+\u{E007F})?)\$',
  unicode: true,
);

/// Counts one to three stand-alone emoji. Limit the input before segmenting:
/// even a single grapheme can contain thousands of combining marks.
int? emojiOnlyCount(String text) {
  if (text.isEmpty || text.length > 256) return null;
  var count = 0;
  for (final cluster in text.trim().characters) {
    if (++count > 3 || !_emoji.hasMatch(cluster)) return null;
  }
  return count == 0 ? null : count;
}
