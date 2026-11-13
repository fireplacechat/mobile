import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/db/local_messages.dart';

class TimelineScroll extends ChangeNotifier {
  TimelineScroll({required this.isMounted}) {
    controller.addListener(_onTimelineScroll);
  }
  final bool Function() isMounted;
  final controller = ScrollController();
  final viewportKey = GlobalKey();
  final _anchors = <String, GlobalKey>{};
  bool _awayFromLatest = false;
  bool _disposed = false;
  Object? _latestScroll;
  bool get awayFromLatest => _awayFromLatest;

  /// Scrolled this far up from the newest message, the view counts as away
  /// from it: it no longer follows new messages.
  static const awayThreshold = 96.0;

  /// The message briefly highlighted after a jump to it, or null.
  final flashed = ValueNotifier<String?>(null);
  Timer? _flashTimer;

  /// How long a jumped-to message stays highlighted.
  static const flashFor = Duration(milliseconds: 1400);

  /// Highlights [id] for [flashFor], so the eye finds it after a jump.
  void flash(String id) {
    if (_disposed) return;
    _flashTimer?.cancel();
    flashed.value = id;
    _flashTimer = Timer(flashFor, () {
      if (!_disposed && flashed.value == id) flashed.value = null;
    });
  }

  /// True while the view animates back to the newest message after one's own
  /// send. A message stored meanwhile must not be taken for an arrival while
  /// reading, which would hold the view where it was.
  bool get returningToLatest => _latestScroll != null;

  void _onTimelineScroll() {
    final away = controller.hasClients && controller.offset > awayThreshold;
    if (away != _awayFromLatest && isMounted()) {
      _awayFromLatest = away;
      if (!_disposed) notifyListeners();
    }
  }

  (GlobalKey, double)? readingAnchor() {
    final viewport = viewportKey.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) return null;
    final top = viewport.localToGlobal(Offset.zero).dy;
    final bottom = top + viewport.size.height;
    (GlobalKey, double)? anchor;
    for (final key in _anchors.values) {
      final box = key.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize || !box.attached) continue;
      final y = box.localToGlobal(Offset.zero).dy;
      if (y < bottom &&
          y + box.size.height > top &&
          (anchor == null || (y - top).abs() < (anchor.$2 - top).abs())) {
        anchor = (key, y);
      }
    }
    return anchor;
  }

  void keepReadingAnchor((GlobalKey, double) anchor) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed ||
          !isMounted() ||
          !controller.hasClients ||
          controller.offset <= awayThreshold) {
        return;
      }
      final box = anchor.$1.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize || !box.attached) return;
      // The reversed timeline grows upwards. Restore the visible message's
      // position rather than the numeric offset from its changing bottom.
      final shift = box.localToGlobal(Offset.zero).dy - anchor.$2;
      final target = (controller.offset - shift).clamp(
        0.0,
        controller.position.maxScrollExtent,
      );
      if (shift.abs() > .5) controller.jumpTo(target);
    });
  }

  /// The user just sent something: show it, even if they had scrolled up to read older messages
  /// (a message that ARRIVES while reading still never moves the view).
  void showNewestAfterOwnSend(void Function() latest) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed && isMounted()) latest();
    });
  }

  void scrollToLatest({required bool reduceMotion}) {
    if (_disposed) return;
    if (!controller.hasClients) return;
    if (reduceMotion) {
      _latestScroll = null;
      controller.jumpTo(0);
    } else {
      final scroll = Object();
      _latestScroll = scroll;
      controller
          .animateTo(
            0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
          )
          .whenComplete(() {
            // A second send can replace the animation before it finishes.
            if (identical(_latestScroll, scroll)) _latestScroll = null;
          });
    }
  }

  void pruneAnchors(Set<String> visibleIds) {
    _anchors.removeWhere((id, _) => !visibleIds.contains(id));
  }

  /// Locate a lazily built row without walking an unbounded history one screen
  /// at a time. Built row indices bracket the next scroll offset.
  Future<bool> locate(
    String id,
    List<String> orderedIds, {
    required bool reduceMotion,
  }) async {
    final indices = {for (final (index, key) in orderedIds.indexed) key: index};
    final target = indices[id];
    if (target == null) return false;
    double lower = 0;
    double? upper;
    for (var attempt = 0; attempt < 24; attempt++) {
      if (_disposed || !isMounted() || !controller.hasClients) return false;
      final context = _anchors[id]?.currentContext;
      if (context != null && context.mounted) {
        await Scrollable.ensureVisible(
          context,
          alignment: .5,
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 180),
        );
        return true;
      }
      final built = [
        for (final entry in _anchors.entries)
          if (entry.value.currentContext != null &&
              indices.containsKey(entry.key))
            indices[entry.key]!,
      ];
      if (built.isEmpty) return false;
      final oldest = built.reduce((a, b) => a < b ? a : b);
      if (target < oldest) {
        lower = controller.offset;
      } else {
        upper = controller.offset;
      }
      final next = (lower + (upper ?? controller.position.maxScrollExtent)) / 2;
      controller.jumpTo(next.clamp(0, controller.position.maxScrollExtent));
      await WidgetsBinding.instance.endOfFrame;
    }
    return false;
  }

  GlobalKey anchorFor(String messageId) =>
      _anchors.putIfAbsent(messageId, GlobalKey.new);

  /// History changed from [before] to [next]. Someone reading further up
  /// keeps their place; at the bottom, a new last message is followed.
  void historyChanged(
    List<LocalMessage>? before,
    AsyncValue<List<LocalMessage>> next,
  ) {
    if (!controller.hasClients || next.hasError) return;
    if (controller.offset > awayThreshold && !returningToLatest) {
      final anchor = readingAnchor();
      if (anchor != null) keepReadingAnchor(anchor);
      return;
    }
    final after = next.value;
    if (after == null ||
        after.isEmpty ||
        (before != null &&
            before.isNotEmpty &&
            before.last.id == after.last.id)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => jumpToLatestIfNear());
  }

  void jumpToLatestIfNear() {
    if (!_disposed &&
        isMounted() &&
        controller.hasClients &&
        controller.offset <= awayThreshold) {
      controller.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _flashTimer?.cancel();
    flashed.dispose();
    controller.removeListener(_onTimelineScroll);
    controller.dispose();
    super.dispose();
  }
}
