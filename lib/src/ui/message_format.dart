import 'package:flutter/material.dart';

import 'package:fireplace/src/model/chat/message_limits.dart';

/// Untrusted oversized messages stay literal everywhere they are displayed.
FormattedMessage displayMessage(String source) => messageTooLong(source)
    ? FormattedMessage([FormatRun(source, false, false, false)])
    : formatMessage(source);

/// Previews are bounded before painting; expanded bubbles alone show full text.
String messagePreview(String source) {
  final plain = displayMessage(source).plain;
  return plain.runes.take(oversizedPreviewCharacters + 1).length >
          oversizedPreviewCharacters
      ? '${clipMessage(plain, oversizedPreviewCharacters)}…'
      : plain;
}

/// Small, bounded inline grammar. No HTML, links, fetching or protocol changes.
/// Matched markers are hidden; unmatched markers and intra-word underscores stay literal.
class FormattedMessage {
  FormattedMessage(this.runs);
  final List<FormatRun> runs;
  String get plain => runs.map((r) => r.text).join();
  TextSpan span(TextStyle base) => TextSpan(
    style: base,
    children: [
      for (final r in runs)
        TextSpan(
          text: r.text,
          style: TextStyle(
            fontWeight: r.bold ? FontWeight.w700 : null,
            fontStyle: r.italic ? FontStyle.italic : null,
            decoration: r.strike ? TextDecoration.lineThrough : null,
          ),
        ),
    ],
  );
}

class FormatRun {
  FormatRun(this.text, this.bold, this.italic, this.strike);
  String text;
  final bool bold, italic, strike;
}

class _Token {
  _Token(this.text, this.marker, this.open, this.close);
  final String text;
  final String? marker;
  final bool open, close;
}

FormattedMessage formatMessage(String source) {
  final tokens = <_Token>[];
  final literal = StringBuffer();
  void flushLiteral() {
    if (literal.isNotEmpty) {
      tokens.add(_Token(literal.toString(), null, false, false));
      literal.clear();
    }
  }

  final whitespace = RegExp(r'\s');
  final words = RegExp(r'[\p{L}\p{N}\p{M}_]', unicode: true);
  bool space(String s) => s.isEmpty || whitespace.hasMatch(s);
  bool word(String s) => words.hasMatch(s);
  String beforeAt(int at) {
    if (at == 0) return '';
    final low = source.codeUnitAt(at - 1);
    return source.substring(
      at > 1 && low >= 0xdc00 && low <= 0xdfff ? at - 2 : at - 1,
      at,
    );
  }

  String afterAt(int at) {
    if (at == source.length) return '';
    final high = source.codeUnitAt(at);
    return source.substring(
      at,
      at + (at + 1 < source.length && high >= 0xd800 && high <= 0xdbff ? 2 : 1),
    );
  }

  for (var i = 0; i < source.length;) {
    if (source[i] == r'\' &&
        i + 1 < source.length &&
        r'\*_~'.contains(source[i + 1])) {
      literal.write(source[i + 1]);
      i += 2;
      continue;
    }
    final marker = source.startsWith('**', i)
        ? '**'
        : source.startsWith('~~', i)
        ? '~~'
        : source[i] == '_'
        ? '_'
        : null;
    if (marker == null) {
      literal.write(source[i]);
      i++;
      continue;
    }
    final before = beforeAt(i);
    final end = i + marker.length;
    final after = afterAt(end);
    if (marker == '_' && (before == '_' || after == '_')) {
      literal.write(marker);
      i = end;
      continue;
    }
    flushLiteral();
    tokens.add(
      _Token(
        marker,
        marker,
        !space(after) && (marker != '_' || !word(before)),
        !space(before) && (marker != '_' || !word(after)),
      ),
    );
    i = end;
  }
  flushLiteral();
  final stack = <int>[];
  final pairs = <int, int>{};
  for (var i = 0; i < tokens.length; i++) {
    final t = tokens[i];
    if (t.marker == null) continue;
    if (t.close && stack.isNotEmpty && tokens[stack.last].marker == t.marker) {
      final start = stack.removeLast();
      if (i > start + 1) {
        pairs[start] = i;
        pairs[i] = start;
      }
    } else if (t.open) {
      stack.add(i);
    }
  }
  // Counts instead of a list: membership tests and removals stay O(1) however deep markers nest.
  final active = <String, int>{'**': 0, '_': 0, '~~': 0};
  final runs = <FormatRun>[];
  final buffer = StringBuffer();
  void flush() {
    if (buffer.isEmpty) return;
    runs.add(
      FormatRun(
        buffer.toString(),
        active['**']! > 0,
        active['_']! > 0,
        active['~~']! > 0,
      ),
    );
    buffer.clear();
  }

  for (var i = 0; i < tokens.length; i++) {
    final other = pairs[i];
    if (other != null) {
      flush();
      if (other > i) {
        active[tokens[i].marker!] = active[tokens[i].marker!]! + 1;
      } else {
        active[tokens[i].marker!] = active[tokens[i].marker!]! - 1;
      }
    } else {
      buffer.write(tokens[i].text);
    }
  }
  flush();
  return FormattedMessage(runs);
}
