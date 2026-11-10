import 'package:flutter/material.dart';
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

/// "Delete All" in selection. Removes the conversation's messages on this
/// device. It does not ask anyone else's device to delete them.
Future<bool> showDeleteAllMessagesSheet(BuildContext context) async {
  final choice = await showFireplaceActionSheet<bool>(
    context,
    title: 'Delete all messages in the chat?',
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
      return Padding(
        padding: EdgeInsets.only(top: 8, bottom: keyboard),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: t.panel,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 22, 16, 12 + bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: Theme.of(ctx).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w600, height: 1.25),
                ),
                const SizedBox(height: 18),
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
                        textStyle: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onPressed: () => Navigator.pop(ctx, action.value),
                      child: Text(action.label),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}
