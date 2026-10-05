import 'package:flutter/services.dart';

import '../services/message_limits.dart';

/// Code-point limit, preserving the existing suffix when inserting/pasting.
/// Combining marks and ZWJ sequences count by their constituent code points.
class MessageInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!messageTooLong(newValue.text)) return newValue;
    final old = oldValue.text.runes.toList(),
        next = newValue.text.runes.toList();
    var prefix = 0, suffix = 0;
    while (prefix < old.length &&
        prefix < next.length &&
        old[prefix] == next[prefix]) {
      prefix++;
    }
    while (suffix < old.length - prefix &&
        suffix < next.length - prefix &&
        old[old.length - 1 - suffix] == next[next.length - 1 - suffix]) {
      suffix++;
    }
    // Programmatically supplied overlong old text is not a valid draft.
    if (prefix + suffix > maxMessageCharacters) {
      prefix = 0;
      suffix = 0;
    }
    final allowed = maxMessageCharacters - prefix - suffix;
    final cutStart = String.fromCharCodes(next.take(prefix + allowed)).length;
    final cutEnd =
        newValue.text.length -
        String.fromCharCodes(next.skip(next.length - suffix)).length;
    final clipped =
        newValue.text.substring(0, cutStart) + newValue.text.substring(cutEnd);
    int adjust(int offset) => offset <= cutStart
        ? offset
        : offset >= cutEnd
        ? offset - (cutEnd - cutStart)
        : cutStart;
    final composing = newValue.composing;
    return TextEditingValue(
      text: clipped,
      selection: TextSelection(
        baseOffset: adjust(newValue.selection.baseOffset),
        extentOffset: adjust(newValue.selection.extentOffset),
        affinity: newValue.selection.affinity,
        isDirectional: newValue.selection.isDirectional,
      ),
      composing:
          composing.isValid &&
              (composing.end <= cutStart || composing.start >= cutEnd)
          ? TextRange(
              start: adjust(composing.start),
              end: adjust(composing.end),
            )
          : TextRange.empty,
    );
  }
}
