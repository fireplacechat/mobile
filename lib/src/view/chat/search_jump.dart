import 'package:flutter/widgets.dart';

import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/view/chat/timeline_scroll.dart';

/// A chat opened from a search result: once the history has loaded, scroll
/// to the message and highlight it. The whole conversation stays on screen
/// and scrollable. Newer messages count as seen only once the person scrolls
/// down to them.
class SearchJump {
  SearchJump(String? messageId) : _pending = messageId, _seenUpTo = messageId;

  /// The result still to jump to once the history has loaded.
  String? _pending;

  /// Messages up to this one count as seen, until the newest are reached.
  String? _seenUpTo;

  /// The jump is still scrolling.
  bool _running = false;

  /// Starts the jump once [loaded]. [unavailable] is called when the result
  /// is not in [history] any more; [done] after the jump.
  void runOnceLoaded(
    List<LocalMessage> history, {
    required bool loaded,
    required TimelineScroll timeline,
    required bool reduceMotion,
    required bool Function() isMounted,
    required VoidCallback unavailable,
    required VoidCallback done,
  }) {
    final id = _pending;
    if (id == null || !loaded) return;
    _pending = null;
    if (!history.any((m) => m.id == id)) {
      _seenUpTo = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => unavailable());
      return;
    }
    final ids = history.map((m) => m.id).toList();
    _running = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!isMounted()) return;
      final found = await timeline.locate(id, ids, reduceMotion: reduceMotion);
      if (!isMounted()) return;
      _running = false;
      if (found) timeline.flash(id);
      done();
    });
  }

  /// The last message to count as seen, or null for all of them.
  String? seenUpTo({required bool awayFromLatest}) {
    if (_seenUpTo != null && _pending == null && !_running && !awayFromLatest) {
      _seenUpTo = null; // scrolled down to the newest messages
    }
    return _seenUpTo;
  }

  /// The person went to the newest messages themselves.
  void reachedLatest() => _seenUpTo = null;
}
