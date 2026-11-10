import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/chat/message_selection.dart';
import 'package:fireplace/src/model/chat/message_controls.dart';
import 'package:fireplace/src/model/chat/chat_service.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/widgets/app_bar.dart';
import 'package:fireplace/src/widgets/dialog.dart';

class MessageSelectionSurface extends ConsumerWidget {
  const MessageSelectionSurface({
    super.key,
    required this.chatId,
    required this.appBar,
    required this.body,
    required this.onDeleted,
  });
  final String chatId;
  final PreferredSizeWidget appBar;
  final Widget body;
  final void Function(Set<String>) onDeleted;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final owner = ref.read(appSessionProvider).value;
    final controller = ref.read(messageSelectionProvider(chatId).notifier);
    final count = ref.read(messageSelectionProvider(chatId)).ids.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => UiDialog(
        title: Text('Delete ${count == 1 ? 'message' : '$count messages'}?'),
        content: const Text('This only deletes messages from this device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('confirmDeleteForMe'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Delete for me',
              style: TextStyle(color: FireplaceUiTokens.of(ctx).danger),
            ),
          ),
        ],
      ),
    );
    if (!context.mounted ||
        confirmed != true ||
        !identical(ref.read(appSessionProvider).value, owner)) {
      return;
    }
    final removed = await controller.deleteSelected();
    if (!context.mounted ||
        !identical(ref.read(appSessionProvider).value, owner)) {
      return;
    }
    onDeleted(removed);
    final error = ref.read(messageSelectionProvider(chatId)).error;
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(messageControlsProvider(chatId).select((s) => s.busy));
    ref.listen(messageControlsProvider(chatId), (previous, next) {
      if (next.notice == null || next.notice == previous?.notice) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(next.notice!),
          action: next.pending == null
              ? null
              : SnackBarAction(
                  label:
                      next.pending!.outcome ==
                          SendOutcome.publishedLocalSaveFailed
                      ? 'Save on device'
                      : 'Check status',
                  onPressed: () => ref
                      .read(messageControlsProvider(chatId).notifier)
                      .resolvePending(),
                ),
        ),
      );
    });
    final selection = ref.watch(messageSelectionProvider(chatId));
    final controller = ref.read(messageSelectionProvider(chatId).notifier);
    return PopScope(
      canPop: !selection.active,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) controller.clear();
      },
      child: Scaffold(
        appBar: selection.active
            ? UiAppBar(
                context: context,
                leading: IconButton(
                  key: const Key('exitMessageSelection'),
                  tooltip: 'Cancel selection',
                  onPressed: selection.deleting ? null : controller.clear,
                  icon: const Icon(Icons.close),
                ),
                title: Text(
                  '${selection.ids.length} selected',
                  key: const Key('selectionCount'),
                ),
                actions: [
                  IconButton(
                    key: const Key('deleteSelectedMessages'),
                    tooltip: 'Delete',
                    onPressed: selection.deleting
                        ? null
                        : () => _delete(context, ref),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              )
            : appBar,
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: selection.active ? controller.clear : null,
          child: body,
        ),
      ),
    );
  }
}
