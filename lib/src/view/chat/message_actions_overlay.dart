import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/view/chat/message_actions.dart';

/// A lifted message and its actions share an edge, even near the keyboard.
class MessageActionsOverlay extends StatelessWidget {
  const MessageActionsOverlay({
    super.key,
    required this.anchor,
    required this.actions,
    required this.animation,
    this.preview,
  });

  final Rect anchor;
  final List<MessageAction> actions;
  final Animation<double> animation;
  final Widget? preview;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final theme = Theme.of(context);
    final tokens = theme.extension<FireplaceUiTokens>();
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: ColoredBox(color: Colors.black.withValues(alpha: .22)),
            ),
          ),
        ),
        CustomMultiChildLayout(
          delegate: _MessageMenuLayout(
            anchor,
            EdgeInsets.fromLTRB(
              media.padding.left + 12,
              media.padding.top + 12,
              media.padding.right + 12,
              math.max(media.padding.bottom, media.viewInsets.bottom) + 12,
            ),
          ),
          children: [
            if (preview != null)
              LayoutId(
                id: _Part.preview,
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: Material(
                      type: MaterialType.transparency,
                      child: SingleChildScrollView(child: preview!),
                    ),
                  ),
                ),
              ),
            LayoutId(
              id: _Part.menu,
              child: ScaleTransition(
                scale: Tween(begin: .8, end: 1.0).animate(
                  CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
                ),
                alignment: anchor.center.dx > media.size.width / 2
                    ? Alignment.topRight
                    : Alignment.topLeft,
                child: Material(
                  key: const Key('messageActionsPanel'),
                  elevation: 12,
                  color: tokens?.panel ?? theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(24),
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final (index, action) in actions.indexed) ...[
                          if (index != 0)
                            Divider(
                              height: 1,
                              thickness: .5,
                              color: tokens?.separator,
                            ),
                          TextButton(
                            key: ValueKey('messageAction-${action.id}'),
                            autofocus: index == 0,
                            onPressed: () => Navigator.pop(context, action),
                            style: ButtonStyle(
                              shape: const WidgetStatePropertyAll(
                                RoundedRectangleBorder(),
                              ),
                              minimumSize: const WidgetStatePropertyAll(
                                Size.fromHeight(48),
                              ),
                              padding: const WidgetStatePropertyAll(
                                EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 12,
                                ),
                              ),
                              foregroundColor: WidgetStatePropertyAll(
                                action.destructive
                                    ? tokens?.danger ?? theme.colorScheme.error
                                    : tokens?.text ??
                                          theme.colorScheme.onSurface,
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    action.label,
                                    style: const TextStyle(fontSize: 17),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Icon(action.icon, size: 22),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

enum _Part { preview, menu }

class _MessageMenuLayout extends MultiChildLayoutDelegate {
  _MessageMenuLayout(this.anchor, this.insets);
  final Rect anchor;
  final EdgeInsets insets;

  @override
  void performLayout(Size size) {
    final area = Rect.fromLTRB(
      insets.left,
      insets.top,
      math.max(insets.left, size.width - insets.right),
      math.max(insets.top, size.height - insets.bottom),
    );
    final hasPreview = hasChild(_Part.preview);
    final menu = layoutChild(
      _Part.menu,
      BoxConstraints(
        minWidth: math.min(250, area.width),
        maxWidth: math.min(250, area.width),
        maxHeight: area.height * (hasPreview ? .7 : 1),
      ),
    );
    const gap = 8.0;
    final preview = hasPreview
        ? layoutChild(
            _Part.preview,
            BoxConstraints(
              maxWidth: math.min(anchor.width, area.width),
              maxHeight: math.max(0, area.height - menu.height - gap),
            ),
          )
        : Size.zero;
    final right = anchor.center.dx > size.width / 2;
    double x(double width) => (right ? anchor.right - width : anchor.left)
        .clamp(area.left, math.max(area.left, area.right - width));
    final height = preview.height + (hasPreview ? gap : 0) + menu.height;
    final top = anchor.top
        .clamp(area.top, math.max(area.top, area.bottom - height))
        .toDouble();
    if (hasPreview) positionChild(_Part.preview, Offset(x(preview.width), top));
    positionChild(
      _Part.menu,
      Offset(x(menu.width), top + preview.height + (hasPreview ? gap : 0)),
    );
  }

  @override
  bool shouldRelayout(_MessageMenuLayout oldDelegate) =>
      anchor != oldDelegate.anchor || insets != oldDelegate.insets;
}
