import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'package:fireplace/src/view/chat/message_menu_parts.dart';
import 'package:fireplace/src/view/chat/message_menu_placement.dart';

/// Marks which piece of the held-message menu a child is.
class MessageMenuId extends ParentDataWidget<MessageMenuParentData> {
  const MessageMenuId({required this.id, required super.child, super.key});

  final String id;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as MessageMenuParentData;
    if (data.id == id) return;
    data.id = id;
    final parent = renderObject.parent;
    if (parent is RenderObject) parent.markNeedsLayout();
  }

  @override
  Type get debugTypicalAncestorWidgetClass => MessageMenuStack;
}

class MessageMenuParentData extends ContainerBoxParentData<RenderBox> {
  String id = '';
}

/// Lays out the held message, reaction bar and action list together.
///
/// The message is scaled when it is painted, not squeezed into a narrower
/// width, so its text does not reflow while the menu is open.
class MessageMenuStack extends MultiChildRenderObjectWidget {
  const MessageMenuStack({
    super.key,
    required this.anchor,
    required this.insets,
    required this.shift,
    required this.picker,
    required this.pickerTop,
    required super.children,
  });

  final Rect anchor;
  final EdgeInsets insets;
  final Animation<double> shift;
  final Animation<double> picker;
  final double pickerTop;

  @override
  RenderMessageMenu createRenderObject(BuildContext context) =>
      RenderMessageMenu(
        anchor: anchor,
        insets: insets,
        shift: shift,
        picker: picker,
        pickerTop: pickerTop,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderMessageMenu renderObject,
  ) {
    renderObject
      ..anchor = anchor
      ..insets = insets
      ..shift = shift
      ..picker = picker
      ..pickerTop = pickerTop;
  }
}

class RenderMessageMenu extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, MessageMenuParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, MessageMenuParentData> {
  RenderMessageMenu({
    required this._anchor,
    required this._insets,
    required this._shift,
    required this._picker,
    required this._pickerTop,
  });

  Rect _anchor;
  EdgeInsets _insets;
  Animation<double> _shift;
  Animation<double> _picker;
  double _pickerTop;
  double _previewScale = 1;
  bool _alignEnd = false;

  /// Scale of the held message at the current frame. One means full size.
  double get previewScale => _previewScale;

  set anchor(Rect value) {
    if (_anchor == value) return;
    _anchor = value;
    markNeedsLayout();
  }

  set insets(EdgeInsets value) {
    if (_insets == value) return;
    _insets = value;
    markNeedsLayout();
  }

  set pickerTop(double value) {
    if (_pickerTop == value) return;
    _pickerTop = value;
    markNeedsLayout();
  }

  set shift(Animation<double> value) {
    if (identical(_shift, value)) return;
    if (attached) _shift.removeListener(markNeedsLayout);
    _shift = value;
    if (attached) _shift.addListener(markNeedsLayout);
    markNeedsLayout();
  }

  set picker(Animation<double> value) {
    if (identical(_picker, value)) return;
    if (attached) _picker.removeListener(markNeedsLayout);
    _picker = value;
    if (attached) _picker.addListener(markNeedsLayout);
    markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _shift.addListener(markNeedsLayout);
    _picker.addListener(markNeedsLayout);
  }

  @override
  void detach() {
    _shift.removeListener(markNeedsLayout);
    _picker.removeListener(markNeedsLayout);
    super.detach();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! MessageMenuParentData) {
      child.parentData = MessageMenuParentData();
    }
  }

  RenderBox? _child(String id) {
    var child = firstChild;
    while (child != null) {
      final data = child.parentData! as MessageMenuParentData;
      if (data.id == id) return child;
      child = data.nextSibling;
    }
    return null;
  }

  Size _layout(RenderBox child, BoxConstraints constraints) {
    child.layout(constraints, parentUsesSize: true);
    return child.size;
  }

  @override
  void performLayout() {
    size = constraints.biggest;
    final area = Rect.fromLTRB(
      _insets.left,
      _insets.top,
      math.max(_insets.left, size.width - _insets.right),
      math.max(_insets.top, size.height - _insets.bottom),
    );
    final reactions = _child('reactions');
    final preview = _child('preview');
    final menu = _child('menu');
    final width = math.max(0.0, area.width);
    final height = math.max(0.0, area.height);
    final barExtent = math.min(MessageMenuMetrics.barHeight, height);
    final reactionSize = reactions == null
        ? Size.zero
        : _layout(
            reactions,
            BoxConstraints(
              maxWidth: width,
              minHeight: barExtent,
              maxHeight: barExtent,
            ),
          );
    final menuWidth = math.min(MessageMenuMetrics.menuWidth, width);
    final menuCeiling = math.max(
      0.0,
      height -
          (reactionSize == Size.zero
              ? 0
              : reactionSize.height + MessageMenuMetrics.gap) -
          MessageMenuMetrics.gap,
    );
    final menuSize = menu == null
        ? Size.zero
        : _layout(
            menu,
            BoxConstraints(
              minWidth: menuWidth,
              maxWidth: menuWidth,
              maxHeight: menuCeiling,
            ),
          );
    final previewLimit = _anchor.width > 0
        ? math.min(_anchor.width, width)
        : width;
    final natural = preview == null
        ? Size.zero
        : _layout(preview, BoxConstraints(maxWidth: previewLimit));
    _alignEnd = _anchor.center.dx > size.width / 2;
    final beside = size.width > size.height;
    final settled = placeMessageMenu(
      area: area,
      anchor: _anchor,
      preview: natural,
      reactions: reactionSize,
      menu: menuSize,
      alignEnd: _alignEnd,
      menuBeside: beside,
    );
    final t = _shift.value.clamp(0.0, 1.0);
    final start = _alignEnd
        ? Rect.fromLTWH(
            _anchor.right - natural.width,
            _anchor.top,
            natural.width,
            natural.height,
          )
        : Rect.fromLTWH(
            _anchor.left,
            _anchor.top,
            natural.width,
            natural.height,
          );
    var previewNow = Rect.lerp(start, settled.preview, t)!;
    if (preview != null && _picker.value > 0 && previewNow.height > 0) {
      final above = math.max(
        area.top,
        math.min(
          previewNow.top,
          _pickerTop - MessageMenuMetrics.gap - previewNow.height,
        ),
      );
      previewNow = previewNow.shift(
        Offset(0, (above - previewNow.top) * _picker.value),
      );
    }
    final scale = natural.height == 0
        ? 1.0
        : previewNow.height / natural.height;
    _previewScale = scale.isFinite && scale > 0 ? scale : 1;
    if (preview != null) {
      final data = preview.parentData! as MessageMenuParentData;
      data.offset = _alignEnd
          ? Offset(previewNow.right - natural.width, previewNow.top)
          : previewNow.topLeft;
    }
    if (reactions != null && settled.reactions != null) {
      final startBar = rectForMessageMenuPart(
        part: MessageMenuPart.reactions,
        preview: start,
        size: reactionSize,
        alignEnd: _alignEnd,
        menuBeside: beside,
      );
      (reactions.parentData! as MessageMenuParentData).offset = Rect.lerp(
        startBar,
        settled.reactions!,
        t,
      )!.topLeft;
    }
    if (menu != null) {
      final startMenu = rectForMessageMenuPart(
        part: MessageMenuPart.menu,
        preview: start,
        size: menuSize,
        alignEnd: _alignEnd,
        menuBeside: beside,
      );
      (menu.parentData! as MessageMenuParentData).offset = Rect.lerp(
        startMenu,
        settled.menu,
        t,
      )!.topLeft;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final preview = _child('preview');
    final reactions = _child('reactions');
    final menu = _child('menu');
    if (preview != null) _paintChild(context, offset, preview);
    if (reactions != null) _paintChild(context, offset, reactions);
    if (menu != null) _paintChild(context, offset, menu);
  }

  void _paintChild(PaintingContext context, Offset offset, RenderBox child) {
    final data = child.parentData! as MessageMenuParentData;
    if (data.id != 'preview' || _previewScale == 1) {
      context.paintChild(child, offset + data.offset);
      return;
    }
    final origin = (_alignEnd ? Alignment.topRight : Alignment.topLeft)
        .alongSize(child.size);
    final transform = Matrix4.identity()
      ..translateByDouble(
        data.offset.dx + origin.dx,
        data.offset.dy + origin.dy,
        0,
        1,
      )
      ..scaleByDouble(_previewScale, _previewScale, 1, 1)
      ..translateByDouble(-origin.dx, -origin.dy, 0, 1);
    context.pushTransform(needsCompositing, offset, transform, (
      context,
      offset,
    ) {
      context.paintChild(child, offset);
    });
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final data = child.parentData! as MessageMenuParentData;
    if (data.id == 'preview' && _previewScale != 1) {
      final origin = (_alignEnd ? Alignment.topRight : Alignment.topLeft)
          .alongSize(child.size);
      transform.translateByDouble(
        data.offset.dx + origin.dx,
        data.offset.dy + origin.dy,
        0,
        1,
      );
      transform.scaleByDouble(_previewScale, _previewScale, 1, 1);
      transform.translateByDouble(-origin.dx, -origin.dy, 0, 1);
      return;
    }
    transform.translateByDouble(data.offset.dx, data.offset.dy, 0, 1);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
