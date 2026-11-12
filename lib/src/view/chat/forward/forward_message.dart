import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/chat/chat_service.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/model/notifications/chat_activity.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/widgets/app_bar.dart';
import 'package:fireplace/src/widgets/dialog.dart';
import 'package:fireplace/src/widgets/page.dart';
import 'package:fireplace/src/widgets/status.dart';
import 'package:fireplace/src/model/chat/pending_sends.dart';
import 'package:fireplace/src/model/chat/message_limits.dart';
import 'package:fireplace/src/model/keys/key_service.dart';
import 'package:fireplace/src/view/chat/forward/forward_recipients.dart';

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
      builder: (ctx) {
        final height = MediaQuery.sizeOf(ctx).height * 0.55;
        return Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            height: height,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              child: ForwardMessageScreen(message: message, messages: messages),
            ),
          ),
        );
      },
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
    final sheet = ModalRoute.of(context) is ModalBottomSheetRoute;
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: t.panel,
        body: SafeArea(
          // A sheet is already clear of the status bar. Padding for it
          // would open a gap at the top of the panel.
          top: !sheet,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Row(
                  children: [
                    if (sheet)
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
                  data: (list) => ForwardRecipientList(
                    chats: list,
                    query: _query.text,
                    finished: _finished,
                    selected: _selected,
                    busy: _busy,
                    canSend: _canSend,
                    onToggle: (chatId, selected) => setState(() {
                      if (selected) {
                        _selected.remove(chatId);
                      } else {
                        _selected.add(chatId);
                      }
                    }),
                  ),
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
                    IconButton.filled(
                      key: const Key('forwardSend'),
                      tooltip: 'Send message',
                      style: IconButton.styleFrom(
                        minimumSize: const Size(40, 40),
                        fixedSize: const Size(40, 40),
                        shape: const CircleBorder(),
                        backgroundColor: t.accent,
                        foregroundColor: Theme.of(context)
                            .colorScheme
                            .onPrimary,
                      ),
                      onPressed: _busy || _selected.isEmpty || _tooLong
                          ? null
                          : _send,
                      icon: _busy
                          ? SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Theme.of(context).colorScheme.onPrimary,
                              ),
                            )
                          : const Icon(Icons.arrow_upward_rounded),
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
}
