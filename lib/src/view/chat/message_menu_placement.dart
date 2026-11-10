import 'dart:math' as math;
import 'dart:ui';

/// Space between the held message and the reaction bar or the action list.
/// Kept equal to [MessageMenuMetrics.gap].
const messageMenuGap = 12.0;

/// Where the held message, its reaction bar and its action list sit.
///
/// The message stays where it was held when there is room. Otherwise the group
/// shifts, and a message that still does not fit scales down from the edge it
/// is aligned to. These fit rules follow Signal's context menu (AGPL-3.0).
class MessageMenuPlacement {
  const MessageMenuPlacement({
    required this.preview,
    required this.menu,
    required this.scale,
    this.reactions,
  });

  /// Visual rectangle of the message after it has moved and scaled.
  final Rect preview;
  final Rect menu;
  final Rect? reactions;

  /// Uniform scale applied to the message. One means it was not resized.
  final double scale;
}

enum MessageMenuPart { reactions, menu }

/// [menuBeside] is the landscape arrangement: the list sits beside the message
/// instead of under it. The reaction bar stays above either way.
Rect rectForMessageMenuPart({
  required MessageMenuPart part,
  required Rect preview,
  required Size size,
  required bool alignEnd,
  required bool menuBeside,
}) {
  const gap = messageMenuGap;
  if (part == MessageMenuPart.menu && menuBeside) {
    final x = alignEnd ? preview.left - gap - size.width : preview.right + gap;
    return Rect.fromLTWH(x, preview.top, size.width, size.height);
  }
  final above = part == MessageMenuPart.reactions;
  final y = above ? preview.top - gap - size.height : preview.bottom + gap;
  final x = alignEnd ? preview.right - size.width : preview.left;
  return Rect.fromLTWH(x, y, size.width, size.height);
}

const _minScale = 0.1;

MessageMenuPlacement placeMessageMenu({
  required Rect area,
  required Rect anchor,
  required Size preview,
  required Size menu,
  Size reactions = Size.zero,
  required bool alignEnd,
  bool menuBeside = false,
}) {
  final message = Size(math.max(0, preview.width), math.max(0, preview.height));
  var frame = alignEnd
      ? Rect.fromLTWH(
          anchor.right - message.width,
          anchor.top,
          message.width,
          message.height,
        )
      : Rect.fromLTWH(anchor.left, anchor.top, message.width, message.height);
  final showReactions = reactions.width > 0 && reactions.height > 0;
  final showMenu = menu.width > 0 && menu.height > 0;

  Rect partRect(Rect previewFrame, MessageMenuPart part, Size size) =>
      rectForMessageMenuPart(
        part: part,
        preview: previewFrame,
        size: size,
        alignEnd: alignEnd,
        menuBeside: menuBeside,
      );

  Rect union(Rect previewFrame) {
    var box = previewFrame;
    if (showReactions) {
      box = box.expandToInclude(
        partRect(previewFrame, MessageMenuPart.reactions, reactions),
      );
    }
    if (showMenu) {
      box = box.expandToInclude(
        partRect(previewFrame, MessageMenuPart.menu, menu),
      );
    }
    return box;
  }

  var box = union(frame);
  if (box.bottom > area.bottom) {
    frame = frame.shift(Offset(0, area.bottom - box.bottom));
  }
  box = union(frame);
  if (box.top < area.top) {
    frame = frame.shift(Offset(0, area.top - box.top));
  }

  var scale = 1.0;
  void applyScale(double factor) {
    final width = frame.width * factor;
    final height = frame.height * factor;
    frame = alignEnd
        ? Rect.fromLTWH(
            frame.left + frame.width - width,
            frame.top,
            width,
            height,
          )
        : Rect.fromLTWH(frame.left, frame.top, width, height);
    scale *= factor;
  }

  box = union(frame);
  if (box.height > area.height && frame.height > 0) {
    final factor = math.max(
      (frame.height - (box.height - area.height)) / frame.height,
      _minScale,
    );
    applyScale(factor);
  }
  box = union(frame);
  if (box.width > area.width && frame.width > 0) {
    final factor = math.max(
      (frame.width - (box.width - area.width)) / frame.width,
      _minScale,
    );
    applyScale(factor);
  }

  Rect clamp(Rect rect) {
    var x = rect.left;
    var y = rect.top;
    if (rect.bottom > area.bottom) y -= rect.bottom - area.bottom;
    if (rect.right > area.right) x += area.right - rect.right;
    if (rect.left < area.left) x += area.left - rect.left;
    return Rect.fromLTWH(x, y, rect.width, rect.height);
  }

  return MessageMenuPlacement(
    preview: frame,
    scale: message.height == 0 ? 1 : scale,
    reactions: showReactions
        ? clamp(partRect(frame, MessageMenuPart.reactions, reactions))
        : null,
    menu: clamp(
      showMenu
          ? partRect(frame, MessageMenuPart.menu, menu)
          : Rect.fromLTWH(frame.left, frame.bottom, 0, 0),
    ),
  );
}
