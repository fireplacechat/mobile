import 'package:flutter/material.dart';

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
  bool get awayFromLatest => _awayFromLatest;

  void _onTimelineScroll() {
    final away = controller.hasClients && controller.offset > 96;
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
          controller.offset <= 96) {
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
      controller.jumpTo(0);
    } else {
      controller.animateTo(
        0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
  }

  void pruneAnchors(Set<String> visibleIds) {
    _anchors.removeWhere((id, _) => !visibleIds.contains(id));
  }

  GlobalKey anchorFor(String messageId) =>
      _anchors.putIfAbsent(messageId, GlobalKey.new);

  void jumpToLatestIfNear() {
    if (!_disposed &&
        isMounted() &&
        controller.hasClients &&
        controller.offset <= 96) {
      controller.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    controller.removeListener(_onTimelineScroll);
    controller.dispose();
    super.dispose();
  }
}
