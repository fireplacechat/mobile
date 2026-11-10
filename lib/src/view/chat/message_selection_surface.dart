import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/model/chat/message_selection.dart';
import 'package:fireplace/src/model/chat/chat_exceptions.dart';
import 'package:fireplace/src/model/chat/message_controls.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/view/chat/forward/forward_message.dart';
import 'package:fireplace/src/view/chat/message_delete_sheet.dart';
import 'package:fireplace/src/widgets/app_bar.dart';

class MessageSelectionSurface extends ConsumerWidget {
  const MessageSelectionSurface({
    super.key,
    required this.chatId,
    required this.appBar,
    required this.selectionTitle,
    required this.body,
    required this.onDeleted,
  });
  final String chatId;
  final PreferredSizeWidget appBar;
  final Widget selectionTitle;
  final Widget body;
  final void Function(Set<String>) onDeleted;

  List<LocalMessage> _selectedMessages(WidgetRef ref) {
    final ids = ref.read(messageSelectionProvider(chatId)).ids;
    final messages = ref.read(messagesProvider(chatId)).value ?? const [];
    return [
      for (final message in messages)
        if (ids.contains(message.id) && !message.remotelyDeleted) message,
    ];
  }

  Future<void> _afterDelete(
    BuildContext context,
    WidgetRef ref,
    Set<String> removed,
  ) async {
    if (!context.mounted) return;
    onDeleted(removed);
    final error = ref.read(messageSelectionProvider(chatId)).error;
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _deleteSelected(BuildContext context, WidgetRef ref) async {
    final owner = ref.read(appSessionProvider).value;
    final chosen = _selectedMessages(ref);
    if (chosen.isEmpty) return;
    final everyone = chosen.every(
      (message) => message.outgoing && message.status == MessageStatus.ok,
    );
    final choice = await showMessageDeleteSheet(
      context,
      everyone: everyone,
      count: chosen.length,
    );
    if (!context.mounted ||
        choice == null ||
        !identical(ref.read(appSessionProvider).value, owner)) {
      return;
    }
    final controller = ref.read(messageSelectionProvider(chatId).notifier);
    if (choice == MessageDeleteChoice.me) {
      final removed = await controller.deleteSelected();
      if (!context.mounted ||
          !identical(ref.read(appSessionProvider).value, owner)) {
        return;
      }
      await _afterDelete(context, ref, removed);
      return;
    }
    for (final message in chosen) {
      final sent = await ref
          .read(messageControlsProvider(chatId).notifier)
          .delete(message.id);
      if (!context.mounted ||
          !identical(ref.read(appSessionProvider).value, owner)) {
        return;
      }
      if (!sent) break;
    }
    controller.clear();
  }

  Future<void> _deleteAll(BuildContext context, WidgetRef ref) async {
    final owner = ref.read(appSessionProvider).value;
    final confirmed = await showDeleteAllMessagesSheet(context);
    if (!context.mounted ||
        !confirmed ||
        !identical(ref.read(appSessionProvider).value, owner)) {
      return;
    }
    final removed = await ref
        .read(messageSelectionProvider(chatId).notifier)
        .deleteAllLocal();
    if (!context.mounted ||
        !identical(ref.read(appSessionProvider).value, owner)) {
      return;
    }
    await _afterDelete(context, ref, removed);
  }

  Future<void> _forward(BuildContext context, WidgetRef ref) async {
    final chosen = _selectedMessages(ref);
    if (chosen.isEmpty) return;
    final summary = ref.read(chatSummaryProvider(chatId));
    final name = summary == null
        ? ''
        : ref.read(peerUsernameProvider(summary.peerUid)).value ?? '';
    await forwardMessages(context, chosen, name: name);
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
    final count = selection.ids.length;
    final t = FireplaceUiTokens.of(context);
    return PopScope(
      canPop: !selection.active,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) controller.clear();
      },
      child: Scaffold(
        appBar: selection.active
            ? UiAppBar(
                context: context,
                toolbarHeight: 64,
                leading: TextButton(
                  key: const Key('deleteAllMessages'),
                  onPressed: selection.deleting
                      ? null
                      : () => _deleteAll(context, ref),
                  child: const Text('Delete All'),
                ),
                leadingWidth: 120,
                title: selectionTitle,
                actions: [
                  TextButton(
                    key: const Key('exitMessageSelection'),
                    onPressed: selection.deleting ? null : controller.clear,
                    child: const Text('Cancel'),
                  ),
                ],
              )
            : appBar,
        bottomNavigationBar: selection.active
            ? Material(
                color: t.panel,
                child: SafeArea(
                  child: SizedBox(
                    height: 52,
                    child: Row(
                      children: [
                        IconButton(
                          key: const Key('deleteSelectedMessages'),
                          tooltip: 'Delete',
                          onPressed: selection.deleting || count == 0
                              ? null
                              : () => _deleteSelected(context, ref),
                          icon: const Icon(CupertinoIcons.trash),
                        ),
                        Expanded(
                          child: Text(
                            '$count Selected',
                            key: const Key('selectionCount'),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          key: const Key('forwardSelectedMessages'),
                          tooltip: 'Forward',
                          onPressed: selection.deleting || count == 0
                              ? null
                              : () => _forward(context, ref),
                          icon: const Icon(
                            CupertinoIcons.arrowshape_turn_up_right,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : null,
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: selection.active ? controller.clear : null,
          child: body,
        ),
      ),
    );
  }
}
