import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/chat/chat_service.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/ui/chat_activity.dart';
import 'package:fireplace/src/ui/presentation.dart';
import 'package:fireplace/src/model/chat/message_format.dart';
import 'package:fireplace/src/model/chat/pending_sends.dart';
import 'package:fireplace/src/model/chat/message_limits.dart';
import 'package:fireplace/src/model/keys/key_service.dart';

Future<void> forwardMessage(
  BuildContext context,
  LocalMessage message,
  String name,
) async {
  if (!message.outgoing) {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => UiDialog(
        title: const Text('Share this message?'),
        content: Text(
          'You are sharing text @$name wrote to you. It will be sent as a new message from you.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirmForwardSharing'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Choose recipients'),
          ),
        ],
      ),
    );
    if (go != true || !context.mounted) return;
  }
  if (context.mounted) {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ForwardMessageScreen(message: message),
      ),
    );
  }
}

class ForwardMessageScreen extends ConsumerStatefulWidget {
  const ForwardMessageScreen({super.key, required this.message});
  final LocalMessage message;
  @override
  ConsumerState<ForwardMessageScreen> createState() =>
      _ForwardMessageScreenState();
}

class _ForwardMessageScreenState extends ConsumerState<ForwardMessageScreen> {
  final _selected = <String>{};
  final _finished = <String, String>{};
  bool _busy = false;
  String? _error;
  String? _ownerUid;
  bool _canSend(ChatSummary c) =>
      c.chatId != widget.message.chatId &&
      ref.read(peerUsernameProvider(c.peerUid)).value != deletedAccountLabel &&
      ref.read(chatActivityProvider.notifier).eligible(c) &&
      (c.accepted || c.requestCount < ChatService.requestLimit) &&
      !_finished.containsKey(c.chatId);
  Future<void> _send() async {
    if (_busy || _selected.isEmpty || messageTooLong(widget.message.body)) {
      return;
    }
    final session = ref.read(appSessionProvider).value;
    if (session == null || session.uid != _ownerUid) return;
    final pending = ref.read(pendingLocalSendsProvider.notifier);
    final targets = _selected.toList();
    setState(() {
      _busy = true;
      _error = null;
    });
    for (final id in targets) {
      if (!mounted || ref.read(appSessionProvider).value != session) break;
      final summary = ref.read(chatSummaryProvider(id));
      if (summary == null || !_canSend(summary)) {
        setState(() {
          _finished[id] = 'Unavailable — nothing sent';
          _selected.remove(id);
        });
        continue;
      }
      // Also fence the source if its peer is put on hold while selecting recipients.
      final source = ref.read(chatSummaryProvider(widget.message.chatId));
      if (source == null ||
          !ref.read(chatActivityProvider.notifier).eligible(source)) {
        setState(
          () => _error = 'This conversation is on hold or unavailable. Nothing more was forwarded.',
        );
        break;
      }
      try {
        await session.chat.sendText(id, widget.message.body);
        if (mounted) setState(() => _finished[id] = 'Sent');
      } on SendNotConfirmedException catch (e) {
        if (!e.persisted) pending.add(e, ownerUid: session.uid);
        if (mounted) {
          setState(
            () => _finished[id] =
                'Not confirmed — check this chat; do not send again',
          );
        }
      } on IdentityChangedException {
        if (mounted) {
          setState(
            () => _finished[id] =
                'Not sent — review the security code in this chat',
          );
        }
      } on SendRefusedException catch (e) {
        // A server refusal (quota used up, message too large) has its own plain reason.
        if (mounted) setState(() => _finished[id] = 'Not sent — ${e.message}');
      } on ChatException {
        if (mounted) {
          setState(
            () => _finished[id] =
                'Not sent — this chat is unavailable or at its request limit',
          );
        }
      } catch (_) {
        // Unknown failures must never offer an automatic resend.
        if (mounted) {
          setState(
            () => _finished[id] =
                'Could not confirm — check this chat before sending again',
          );
        }
      }
      if (mounted) setState(() => _selected.remove(id));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(appSessionProvider);
    final uid = account.value?.uid;
    _ownerUid ??= uid;
    if (account.isLoading ||
        account.hasError ||
        uid == null ||
        uid != _ownerUid) {
      return Scaffold(
        appBar: UiAppBar(
          context: context,
          title: const Text('Forward message'),
        ),
        body: const Center(child: Text('This account is no longer available.')),
      );
    }
    final chats = ref.watch(chatsProvider);
    ref.watch(chatActivityProvider);
    ref.watch(blockedUidsProvider);
    ref.watch(hiddenChatsProvider);
    ref.watch(identityAlertsProvider);
    final source = ref.watch(chatSummaryProvider(widget.message.chatId));
    if (source == null ||
        !ref.read(chatActivityProvider.notifier).eligible(source)) {
      return Scaffold(
        appBar: UiAppBar(
          context: context,
          title: const Text('Forward message'),
        ),
        body: UiEmptyState(
          title: 'Conversation unavailable',
          message: _error ?? 'Go back to your chats. Messages from blocked or unavailable contacts cannot be forwarded.',
        ),
      );
    }
    return PopScope(
      canPop: true,
      child: Scaffold(
        appBar: UiAppBar(
          context: context,
          title: const Text('Forward message'),
        ),
        body: UiPageScroll(
          children: [
            Text(
              'Send as a new message from you',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  messagePreview(widget.message.body),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_error != null) UiActionError(message: _error!),
            if (messageTooLong(widget.message.body))
              const UiActionError(
                message: 'This message is longer than 16,384 characters and cannot be forwarded.',
              ),
            if (_busy)
              const Text(
                'You can leave this screen. The current send may still complete; remaining recipients will stop.',
              ),
            ...chats.when(
              loading: () => [const Center(child: CircularProgressIndicator())],
              error: (_, _) => [
                const Text('Could not load recipients. Go back and try again.'),
              ],
              data: (list) => [
                if (!list.any(_canSend))
                  const Text(
                    'No available recipients. Accepted chats and outgoing requests with room can receive messages.',
                  ),
                for (final c in list)
                  if (_canSend(c) ||
                      (_finished.containsKey(c.chatId) &&
                          ref.read(chatActivityProvider.notifier).eligible(c)))
                    CheckboxListTile(
                      key: ValueKey('forwardRecipient-${c.chatId}'),
                      title: Text(
                        ref.watch(peerUsernameProvider(c.peerUid)).value ?? '…',
                      ),
                      subtitle: _finished[c.chatId] == null
                          ? null
                          : Text(_finished[c.chatId]!),
                      value: _selected.contains(c.chatId),
                      onChanged: _busy || !_canSend(c)
                          ? null
                          : (v) => setState(() {
                              if (v == true) {
                                _selected.add(c.chatId);
                              } else {
                                _selected.remove(c.chatId);
                              }
                            }),
                    ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('forwardSend'),
              onPressed:
                  _busy ||
                      _selected.isEmpty ||
                      messageTooLong(widget.message.body)
                  ? null
                  : _send,
              child: Text(
                _busy
                    ? 'Forwarding…'
                    : 'Forward to ${_selected.length} ${_selected.length == 1 ? 'chat' : 'chats'}',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Only the message text is shared. No original sender or conversation details are attached.',
            ),
          ],
        ),
      ),
    );
  }
}
