import 'package:flutter/material.dart';

import 'package:fireplace/src/styles/design_tokens.dart';

enum SafetyActionStyle { normal, destructive }

class SafetySheetAction<T> {
  const SafetySheetAction({
    required this.label,
    this.value,
    this.style = SafetyActionStyle.normal,
    this.buttonKey,
  });
  final String label;
  final T? value;
  final SafetyActionStyle style;
  final Key? buttonKey;
}

/// Signal's action sheet: a bottom panel, a title and message, then capsule
/// buttons. Destructive labels are red. Cancel is another capsule, not red.
Future<T?> showSafetyActionSheet<T>({
  required BuildContext context,
  required String title,
  String? message,
  required List<SafetySheetAction<T>> actions,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) =>
        _SafetyActionSheet<T>(title: title, message: message, actions: actions),
  );
}

class _SafetyActionSheet<T> extends StatelessWidget {
  const _SafetyActionSheet({
    required this.title,
    required this.message,
    required this.actions,
  });
  final String title;
  final String? message;
  final List<SafetySheetAction<T>> actions;

  @override
  Widget build(BuildContext context) {
    final t = FireplaceUiTokens.of(context);
    final media = MediaQuery.of(context);
    // The keyboard covers the bottom of a full-height sheet, and that covered
    // area was part of the scroll viewport, so Block could not be scrolled
    // into view. Sit the panel in the space above the keyboard.
    final keyboard = media.viewInsets.bottom;
    final available = (media.size.height - keyboard).clamp(
      0.0,
      media.size.height,
    );
    final tail = keyboard > 0
        ? 20.0
        : (media.viewPadding.bottom > 20 ? media.viewPadding.bottom : 20.0);
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: available),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: t.panel,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16, 8, 16, tail),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: t.text,
                          fontSize: 17,
                          height: 1.25,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (message != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          message!,
                          style: TextStyle(
                            color: t.text,
                            fontSize: 17,
                            height: 1.3,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  _SheetButton(action: actions[i]),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetButton<T> extends StatelessWidget {
  const _SheetButton({required this.action});
  final SafetySheetAction<T> action;

  @override
  Widget build(BuildContext context) {
    final t = FireplaceUiTokens.of(context);
    final destructive = action.style == SafetyActionStyle.destructive;
    return Material(
      color: t.selectedRow,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: action.buttonKey,
        onTap: () => Navigator.pop(context, action.value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Text(
            action.label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: destructive ? t.danger : t.text,
              fontSize: 17,
              height: 1.2,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
