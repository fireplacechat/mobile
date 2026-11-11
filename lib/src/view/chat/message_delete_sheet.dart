import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:fireplace/src/styles/design_tokens.dart';

enum MessageDeleteChoice { me, everyone }

/// The bottom sheet Signal shows for deleting a message.
///
/// [everyone] is set only for a message you sent. Someone else's message
/// can be removed from this device only.
Future<MessageDeleteChoice?> showMessageDeleteSheet(
  BuildContext context, {
  required bool everyone,
  int count = 1,
}) {
  final one = count == 1;
  return showFireplaceActionSheet<MessageDeleteChoice>(
    context,
    title: everyone
        ? 'Who would you like to delete ${one ? 'this message' : 'these messages'} for?'
        : 'Delete ${one ? 'this message' : '$count messages'}?',
    actions: [
      FireplaceSheetAction(
        key: const Key('confirmDeleteForMe'),
        label: 'Delete for Me',
        destructive: true,
        value: MessageDeleteChoice.me,
      ),
      if (everyone)
        FireplaceSheetAction(
          key: const Key('confirmRemoteDelete'),
          label: 'Delete for Everyone',
          destructive: true,
          value: MessageDeleteChoice.everyone,
        ),
      const FireplaceSheetAction(
        key: Key('cancelMessageDelete'),
        label: 'Cancel',
      ),
    ],
  );
}

/// "Delete All" in selection. Messages you sent are deleted for everyone.
/// Messages the other person sent are removed on this device only.
Future<bool> showDeleteAllMessagesSheet(BuildContext context) async {
  final choice = await showFireplaceActionSheet<bool>(
    context,
    title: 'Delete all messages in the chat?',
    message: 'Messages you sent are deleted for everyone. Their messages are removed only on this device.',
    actions: const [
      FireplaceSheetAction(
        key: Key('confirmDeleteAllMessages'),
        label: 'Delete All Messages',
        destructive: true,
        value: true,
      ),
      FireplaceSheetAction(key: Key('cancelDeleteAll'), label: 'Cancel'),
    ],
  );
  return choice == true;
}

class FireplaceSheetAction<T> {
  const FireplaceSheetAction({
    required this.label,
    this.value,
    this.destructive = false,
    this.key,
  });
  final String label;
  final T? value;
  final bool destructive;
  final Key? key;
}

Future<T?> showFireplaceActionSheet<T>(
  BuildContext context, {
  required String title,
  String? message,
  required List<FireplaceSheetAction<T>> actions,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) {
      final t = FireplaceUiTokens.of(ctx);
      final bottom = MediaQuery.paddingOf(ctx).bottom;
      // The sheet sits on the bottom edge, including over an open keyboard,
      // unless this inset lifts it clear.
      final keyboard = MediaQuery.viewInsetsOf(ctx).bottom;
      // Large text can make the explanation taller than the space above the
      // keyboard. That sheet keeps the actions on screen and scrolls the
      // words. Sheets without a message stay a plain column.
      final maxHeight = MediaQuery.sizeOf(ctx).height - keyboard - 8;
      final buttons = <Widget>[
        for (final action in actions) ...[
          SizedBox(
            height: 52,
            child: TextButton(
              key: action.key,
              style: TextButton.styleFrom(
                backgroundColor: t.selectedRow,
                foregroundColor: action.destructive ? t.danger : t.text,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => Navigator.pop(ctx, action.value),
              // The label keeps the theme face. A text style on the
              // button replaces that face, and the preview then draws
              // each word as a solid bar. Large text scales down to
              // one line so the whole label stays visible.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  action.label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ];
      final titleStyle = Theme.of(ctx).textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.w600, height: 1.25);
      final sheetChild = message == null
          ? Padding(
              padding: EdgeInsets.fromLTRB(16, 22, 16, 12 + bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: titleStyle),
                  const SizedBox(height: 18),
                  ...buttons,
                ],
              ),
            )
          : ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: _PinnedActionSheet(
                header: ListView(
                  shrinkWrap: true,
                  primary: false,
                  padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
                  physics: const ClampingScrollPhysics(),
                  children: [
                    Text(title, style: titleStyle),
                    const SizedBox(height: 8),
                    Text(
                      message,
                      style: Theme.of(ctx).textTheme.bodyLarge
                          ?.copyWith(height: 1.3),
                    ),
                  ],
                ),
                footer: Padding(
                  padding: EdgeInsets.fromLTRB(16, 18, 16, 12 + bottom),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: buttons,
                  ),
                ),
              ),
            );
      return Padding(
        padding: EdgeInsets.only(top: 8, bottom: keyboard),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: t.panel,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: sheetChild,
        ),
      );
    },
  );
}

/// Keeps [footer] on screen. [header] scrolls once the two no longer fit.
class _PinnedActionSheet extends MultiChildRenderObjectWidget {
  _PinnedActionSheet({required Widget header, required Widget footer})
    : super(children: [header, footer]);

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderPinnedActionSheet();
  }
}

class _SheetParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderPinnedActionSheet extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _SheetParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _SheetParentData> {
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SheetParentData) {
      child.parentData = _SheetParentData();
    }
  }

  @override
  void performLayout() {
    final header = firstChild!;
    final footer = childAfter(header)!;
    final width = constraints.maxWidth;
    footer.layout(BoxConstraints(maxWidth: width), parentUsesSize: true);
    header.layout(BoxConstraints(maxWidth: width), parentUsesSize: true);
    final room = constraints.maxHeight - footer.size.height;
    if (room.isFinite && header.size.height > room) {
      header.layout(
        BoxConstraints(maxWidth: width, maxHeight: room < 0 ? 0 : room),
        parentUsesSize: true,
      );
    }
    size = constraints.constrain(
      Size(width, header.size.height + footer.size.height),
    );
    (header.parentData! as _SheetParentData).offset = Offset.zero;
    (footer.parentData! as _SheetParentData).offset = Offset(
      0,
      header.size.height,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }
}
