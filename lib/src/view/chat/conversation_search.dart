import 'dart:async';

import 'package:flutter/material.dart';

import 'package:fireplace/src/model/search/message_search.dart';
import 'package:fireplace/src/styles/design_tokens.dart';

/// Search inside one conversation, 1:1 or group (issue 246). Matches come
/// from the encrypted history on this phone, newest first, and the person
/// steps through them: up for older, down for newer. Nothing is sent
/// anywhere.
class ConversationSearch extends ChangeNotifier {
  ConversationSearch({required this.find, required this.jump});

  /// The matching message ids, newest first, at most [limit] + 1 of them.
  final Future<List<String>> Function(String query, int limit) find;

  /// Scrolls the conversation to a message and lights it up.
  final Future<void> Function(String id) jump;

  /// Matches counted and stepped through; more show as "100+".
  static const limit = 100;
  static const debounce = Duration(milliseconds: 250);

  bool active = false;
  String query = '';
  List<String> hits = const [];

  /// Which match is shown: 0 is the newest.
  int index = 0;

  /// More matched than [limit].
  bool capped = false;
  bool searching = false;

  Timer? _timer;
  int _generation = 0;
  bool _disposed = false;

  void open() {
    if (active) return;
    active = true;
    _changed();
  }

  /// Closes the bar; the conversation stays where it is.
  void close() {
    _timer?.cancel();
    _generation++;
    active = false;
    query = '';
    hits = const [];
    index = 0;
    capped = false;
    searching = false;
    _changed();
  }

  /// The text in the field changed: search once typing pauses.
  void type(String text) {
    query = text;
    _timer?.cancel();
    final generation = ++_generation;
    if (text.trim().isEmpty) {
      hits = const [];
      capped = false;
      searching = false;
      _changed();
      return;
    }
    searching = true;
    _changed();
    _timer = Timer(debounce, () => _run(text, generation));
  }

  Future<void> _run(String text, int generation) async {
    List<String> found;
    try {
      found = await find(text, limit);
    } catch (_) {
      found = const [];
    }
    if (_disposed || generation != _generation) return;
    capped = found.length > limit;
    hits = found.take(limit).toList();
    index = 0;
    searching = false;
    _changed();
    if (hits.isNotEmpty) await jump(hits.first);
  }

  bool get canOlder => index + 1 < hits.length;
  bool get canNewer => index > 0;

  Future<void> older() => _step(1);
  Future<void> newer() => _step(-1);

  Future<void> _step(int by) async {
    final next = index + by;
    if (next < 0 || next >= hits.length) return;
    index = next;
    _changed();
    await jump(hits[next]);
  }

  /// "3 of 12", "1 of 100+", "No matches", or nothing while typing.
  String get label {
    if (query.trim().isEmpty || searching) return '';
    if (hits.isEmpty) return 'No matches';
    return '${index + 1} of ${hits.length}${capped ? '+' : ''}';
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

/// Closes the search, in place of the app bar's back button.
class ConversationSearchClose extends StatelessWidget {
  const ConversationSearchClose({super.key, required this.search});
  final ConversationSearch search;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const Key('conversationSearchClose'),
    icon: const Icon(Icons.close),
    onPressed: search.close,
  );
}

/// The search field, in place of the conversation's title.
class ConversationSearchField extends StatelessWidget {
  const ConversationSearchField({super.key, required this.search});
  final ConversationSearch search;

  @override
  Widget build(BuildContext context) => TextField(
    key: const Key('conversationSearchField'),
    autofocus: true,
    textInputAction: TextInputAction.search,
    onChanged: search.type,
    // The keyboard's search key steps to the next older match.
    onSubmitted: (_) => search.older(),
    style: const TextStyle(fontSize: 17),
    decoration: const InputDecoration(
      hintText: 'Search this chat',
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      filled: false,
      isDense: true,
    ),
  );
}

/// The count, then up for an older match and down for a newer one.
class ConversationSearchControls extends StatelessWidget {
  const ConversationSearchControls({super.key, required this.search});
  final ConversationSearch search;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        search.label,
        key: const Key('conversationSearchCount'),
        style: TextStyle(
          fontSize: 14,
          color: FireplaceUiTokens.of(context).secondaryText,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      IconButton(
        key: const Key('conversationSearchOlder'),
        icon: const Icon(Icons.keyboard_arrow_up),
        onPressed: search.canOlder ? search.older : null,
      ),
      IconButton(
        key: const Key('conversationSearchNewer'),
        icon: const Icon(Icons.keyboard_arrow_down),
        onPressed: search.canNewer ? search.newer : null,
      ),
    ],
  );
}

/// The words being searched for, for the bubbles below to mark. Empty when
/// no search is open.
class SearchHighlight extends InheritedWidget {
  const SearchHighlight({super.key, required this.query, required super.child});
  final String query;

  static String queryOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SearchHighlight>()?.query ??
      '';

  @override
  bool updateShouldNotify(SearchHighlight old) => old.query != query;
}

/// [span] with every match of [query] marked in [mark], matched as the
/// history search matches (folded case, accents kept). Each piece keeps its
/// span's style and tap handling. A match broken by formatting is left
/// unmarked. Linear in the text's length.
InlineSpan markMatches(InlineSpan span, String query, TextStyle mark) {
  final needle = foldForSearch(query.trim());
  if (needle.isEmpty) return span;
  return _mark(span, needle, mark);
}

InlineSpan _mark(InlineSpan span, String needle, TextStyle mark) {
  if (span is! TextSpan) return span;
  final children = [
    for (final child in span.children ?? const <InlineSpan>[])
      _mark(child, needle, mark),
  ];
  final text = span.text ?? '';
  TextSpan piece(String part, {TextStyle? style}) => TextSpan(
    text: part,
    style: style,
    recognizer: span.recognizer,
    mouseCursor: span.mouseCursor,
  );
  final pieces = <InlineSpan>[];
  if (text.isNotEmpty) {
    // Folding can change a character's length, so map offsets back.
    final folded = StringBuffer();
    final starts = <int>[], ends = <int>[];
    var offset = 0;
    for (final rune in text.runes) {
      final original = String.fromCharCode(rune);
      final lower = foldForSearch(original);
      for (var i = 0; i < lower.length; i++) {
        starts.add(offset);
        ends.add(offset + original.length);
      }
      folded.write(lower);
      offset += original.length;
    }
    final haystack = folded.toString();
    var from = 0, done = 0;
    while (true) {
      final at = haystack.indexOf(needle, from);
      if (at < 0) break;
      final start = starts[at], end = ends[at + needle.length - 1];
      if (start > done) pieces.add(piece(text.substring(done, start)));
      pieces.add(piece(text.substring(start, end), style: mark));
      done = end;
      from = at + needle.length;
    }
    if (pieces.isEmpty) {
      if (children.isEmpty) return span;
    } else if (done < text.length) {
      pieces.add(piece(text.substring(done)));
    }
  }
  if (pieces.isEmpty) {
    return TextSpan(
      text: span.text,
      style: span.style,
      recognizer: span.recognizer,
      mouseCursor: span.mouseCursor,
      semanticsLabel: span.semanticsLabel,
      locale: span.locale,
      spellOut: span.spellOut,
      children: children,
    );
  }
  return TextSpan(
    style: span.style,
    semanticsLabel: span.semanticsLabel,
    locale: span.locale,
    spellOut: span.spellOut,
    children: [...pieces, ...children],
  );
}
