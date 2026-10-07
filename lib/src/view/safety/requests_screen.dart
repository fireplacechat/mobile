import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/chat/chat_service.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:fireplace/src/view/safety/confirm_block.dart';
import 'package:fireplace/src/view/safety/report_dialog.dart';
import 'package:fireplace/src/widgets/app_bar.dart';
import 'package:fireplace/src/widgets/avatar.dart';
import 'package:fireplace/src/widgets/page.dart';
import 'package:fireplace/src/widgets/status.dart';

/// People who started a chat with you and are waiting for you to accept.
class RequestsScreen extends ConsumerWidget {
  const RequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(appSessionProvider).value;
    final chatState = ref.watch(chatsProvider);
    if (!chatState.hasValue) {
      return Scaffold(
        appBar: UiAppBar(
          context: context,
          title: const Text('Message requests'),
        ),
        body: chatState.hasError
            ? UiEmptyState(
                title: 'Could not load requests',
                message: 'Try again to load your requests.',
                action: TextButton(
                  onPressed: () => ref.invalidate(chatsProvider),
                  child: const Text('Try again'),
                ),
              )
            : const Center(child: CircularProgressIndicator()),
      );
    }
    final blockedState = ref.watch(blockedUidsProvider);
    final hiddenState = ref.watch(hiddenChatsProvider);
    if (blockedState.isLoading ||
        hiddenState.isLoading ||
        !blockedState.hasValue ||
        !hiddenState.hasValue ||
        blockedState.hasError ||
        hiddenState.hasError) {
      return Scaffold(
        appBar: UiAppBar(
          context: context,
          title: const Text('Message requests'),
        ),
        body: blockedState.isLoading || hiddenState.isLoading
            ? const Center(child: CircularProgressIndicator())
            : UiEmptyState(
                title: 'Could not load requests',
                message: 'Try again to check your conversation preferences.',
                action: TextButton(
                  onPressed: () {
                    ref.invalidate(blockedUidsProvider);
                    ref.invalidate(hiddenChatsProvider);
                  },
                  child: const Text('Try again'),
                ),
              ),
      );
    }
    final chats = chatState.value ?? const [];
    final blocked = blockedState.value ?? const <String>{};
    final hidden = hiddenState.value ?? const <String>{};
    final requests = [
      for (final c in chats)
        if (session != null &&
            c.isIncomingRequest(session.uid) &&
            !blocked.contains(c.peerUid) &&
            !hidden.contains(c.chatId))
          c,
    ];
    return Scaffold(
      appBar: UiAppBar(context: context, title: Text('Message requests')),
      body: requests.isEmpty
          ? const UiEmptyState(
              title: 'No message requests',
              message: 'New requests will appear here. Messages stay hidden until you accept.',
              icon: Icons.mark_email_read_outlined,
            )
          : UiPageScroll(
              children: [
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'These people want to chat. You will not see what they '
                    'wrote until you accept. They cannot see whether you '
                    'have looked.',
                  ),
                ),
                for (final c in requests)
                  _RequestTile(chat: c, session: session!),
              ],
            ),
    );
  }
}

class _RequestTile extends ConsumerStatefulWidget {
  const _RequestTile({required this.chat, required this.session});
  final ChatSummary chat;
  final AppSession session;
  @override
  ConsumerState<_RequestTile> createState() => _RequestTileState();
}

class _RequestTileState extends ConsumerState<_RequestTile> {
  bool _busy = false;
  String? _error;
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not update this request. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = widget.chat, session = widget.session;
    final name = ref.watch(peerUsernameProvider(chat.peerUid)).value ?? '…';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        key: Key('request_${chat.chatId}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: _busy
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(chatId: chat.chatId),
                        ),
                      ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      PersonAvatar(name: name),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '@$name',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const Text('wants to chat'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  FilledButton(
                    key: Key('accept_${chat.chatId}'),
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            await session.chat.acceptRequest(chat.chatId);
                            ref.invalidate(hiddenChatsProvider);
                          }),
                    child: const Text('Accept'),
                  ),
                  OutlinedButton(
                    key: Key('ignore_${chat.chatId}'),
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            await session.safety.hideChat(chat.chatId);
                            ref.invalidate(hiddenChatsProvider);
                          }),
                    child: const Text('Ignore'),
                  ),
                  TextButton(
                    key: Key('block_${chat.chatId}'),
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            if (await confirmBlock(context, name)) {
                              await session.safety.block(chat.peerUid);
                            }
                          }),
                    child: const Text('Block'),
                  ),
                ],
              ),
              TextButton.icon(
                key: Key('report_${chat.chatId}'),
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        await showReportDialog(
                          context,
                          ref,
                          peerUid: chat.peerUid,
                          name: name,
                          chatId: chat.chatId,
                        );
                      }),
                icon: const Icon(Icons.flag_outlined),
                label: const Text('Report'),
              ),
              if (_error != null) UiActionError(message: _error!),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
