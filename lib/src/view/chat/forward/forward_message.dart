import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/chat/chat_service.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/model/notifications/chat_activity.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/widgets/app_bar.dart';
import 'package:fireplace/src/widgets/avatar.dart';
import 'package:fireplace/src/widgets/dialog.dart';
import 'package:fireplace/src/widgets/page.dart';
import 'package:fireplace/src/widgets/status.dart';
import 'package:fireplace/src/model/chat/pending_sends.dart';
import 'package:fireplace/src/model/chat/message_limits.dart';
import 'package:fireplace/src/model/keys/key_service.dart';

Future<void> forwardMessage(
  BuildContext context,
  LocalMessage message,
  String name,
) => forwardMessages(context, [message], name: name);

Future<void> forwardMessages(
  BuildContext context,
  List<LocalMessage> messages, {
  String name = '',
}) async {
  if (messages.isEmpty) return;
  final message = messages.first;
  if (messages.any((item) => !item.outgoing)) {
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
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.92,
        child: ForwardMessageScreen(message: message, messages: messages),
      ),
    );
  }
}

class ForwardMessageScreen extends ConsumerStatefulWidget {
  const ForwardMessageScreen({super.key, required this.message, this.messages});
  final LocalMessage message;

  /// Every message to forward, oldest first. Defaults to [message].
  final List<LocalMessage>? messages;

  List<LocalMessage> get payload => messages ?? [message];
  @override
  ConsumerState<ForwardMessageScreen> createState() =>
      _ForwardMessageScreenState();
}

class _ForwardMessageScreenState extends ConsumerState<ForwardMessageScreen> {
  final _selected = <String>{};
  final _finished = <String, String>{};
  final _query = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _ownerUid;
  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  bool get _tooLong =>
      widget.payload.any((message) => messageTooLong(message.body));

  bool _canSend(ChatSummary c) =>
      c.chatId != widget.message.chatId &&
      ref.read(peerUsernameProvider(c.peerUid)).value != deletedAccountLabel &&
      ref.read(chatActivityProvider.notifier).eligible(c) &&
      (c.accepted || c.requestCount < ChatService.requestLimit) &&
      !_finished.containsKey(c.chatId);
  Future<void> _send() async {
    if (_busy || _selected.isEmpty || _tooLong) {
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
        for (final message in widget.payload) {
          await session.chat.sendText(id, message.body);
        }
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
    final t = FireplaceUiTokens.of(context);
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: t.panel,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Row(
                  children: [
                    if (ModalRoute.of(context) is ModalBottomSheetRoute)
                      const SizedBox(width: 48)
                    else
                      IconButton(
                        tooltip: 'Back',
                        onPressed: () => Navigator.maybePop(context),
                        icon: const Icon(Icons.arrow_back),
                      ),
                    const Expanded(
                      child: Text(
                        'Forward To',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.maybePop(context),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  key: const Key('forwardSearch'),
                  controller: _query,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: t.selectedRow,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: UiActionError(message: _error!),
                ),
              if (_tooLong)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: UiActionError(
                    message: 'This message is longer than 16,384 characters and cannot be forwarded.',
                  ),
                ),
              Expanded(
                child: chats.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) => const Center(
                    child: Text(
                      'Could not load recipients. Go back and try again.',
                    ),
                  ),
                  data: (list) {
                    final shown =
                        [
                          for (final chat in list)
                            if (_canSend(chat) ||
                                (_finished.containsKey(chat.chatId) &&
                                    ref
                                        .read(chatActivityProvider.notifier)
                                        .eligible(chat)))
                              chat,
                        ].where((chat) {
                          final name =
                              ref
                                  .read(peerUsernameProvider(chat.peerUid))
                                  .value ??
                              '';
                          final query = _query.text.trim().toLowerCase();
                          return query.isEmpty ||
                              name.toLowerCase().contains(query);
                        }).toList();
                    final recent =
                        shown
                            .where((chat) => chat.lastMessageAt != null)
                            .toList()
                          ..sort(
                            (a, b) =>
                                b.lastMessageAt!.compareTo(a.lastMessageAt!),
                          );
                    final people = shown
                        .where((chat) => chat.lastMessageAt == null)
                        .toList();
                    if (shown.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No available recipients. Accepted chats and outgoing requests with room can receive messages.',
                          ),
                        ),
                      );
                    }
                    return ListView(
                      children: [
                        if (recent.isNotEmpty) ...[
                          const _ForwardHeading('Recent Chats'),
                          for (final chat in recent) _recipient(chat),
                        ],
                        if (people.isNotEmpty) ...[
                          const _ForwardHeading('People'),
                          for (final chat in people) _recipient(chat),
                        ],
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: Text(
                            'Only the message text is shared. No original sender or conversation details are attached.',
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _selected.isEmpty
                            ? 'Choose a recipient'
                            : 'Send to ${_selected.length}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    FilledButton(
                      key: const Key('forwardSend'),
                      onPressed: _busy || _selected.isEmpty || _tooLong
                          ? null
                          : _send,
                      child: Icon(
                        _busy ? Icons.hourglass_top : Icons.arrow_upward,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _recipient(ChatSummary chat) {
    final name = ref.watch(peerUsernameProvider(chat.peerUid)).value ?? '…';
    final selected = _selected.contains(chat.chatId);
    final done = _finished[chat.chatId];
    final t = FireplaceUiTokens.of(context);
    return InkWell(
      key: ValueKey('forwardRecipient-${chat.chatId}'),
      onTap: _busy || !_canSend(chat)
          ? null
          : () => setState(() {
              if (selected) {
                _selected.remove(chat.chatId);
              } else {
                _selected.add(chat.chatId);
              }
            }),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            PersonAvatar(name: name, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name),
                  if (done != null)
                    Text(done, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? t.accent : Colors.transparent,
                border: Border.all(
                  color: selected ? t.accent : t.secondaryText,
                  width: 1.5,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _ForwardHeading extends StatelessWidget {
  const _ForwardHeading(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleMedium
          ?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}
