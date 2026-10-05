import 'package:flutter/material.dart';

import 'presentation.dart';
import 'lockup.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../services/chat_service.dart';
import '../services/local_messages.dart';
import '../services/safety_service.dart';
import 'chat_screen.dart';
import 'design_tokens.dart';

Future<bool> confirmBlock(BuildContext context, String name) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => UiDialog(
      icon: Icon(
        Icons.block,
        color: FireplaceUiTokens.of(context).danger,
        size: 36,
      ),
      title: Text('Block @$name?'),
      content: Text(
        'They will not be able to start chats or send you messages, and you '
        'will not receive anything more from them. They are not told. You '
        'can unblock them any time in Settings.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('Cancel'),
        ),
        TextButton(
          key: Key('confirmBlock'),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            'Block',
            style: TextStyle(color: FireplaceUiTokens.of(context).danger),
          ),
        ),
      ],
    ),
  );
  return ok == true;
}

String _reasonLabel(ReportReason r) => switch (r) {
  ReportReason.spam => 'Spam or unwanted promotion',
  ReportReason.harassment => 'Harassment or threats',
  ReportReason.abuse => 'Abusive or illegal content',
  ReportReason.impersonation => 'Pretending to be someone else',
  ReportReason.other => 'Something else',
};

/// Reports a person to the app operator. Because messages are end-to-end
/// encrypted, the operator only sees message text the reporter chooses to attach.
Future<bool> showReportDialog(
  BuildContext context,
  WidgetRef ref, {
  required String peerUid,
  required String name,
  String? chatId,

  /// Set when the report starts from one message (long press > Report): the tick box then offers
  /// to include just that message instead of the last ten.
  LocalMessage? focus,
}) async {
  final session = ref.read(appSessionProvider).value;
  if (session == null) return false;
  final sent = await showDialog<bool>(
    context: context,
    builder: (_) => _ReportDialog(
      name: name,
      canIncludeChat: chatId != null,
      aboutMessage: focus != null,
      submit: (input) async {
        void checkAccount() {
          if (!context.mounted ||
              !identical(ref.read(appSessionProvider).value, session)) {
            throw StateError('Account changed');
          }
        }

        checkAccount();
        var context10 = <String>[];
        if (input.include && focus != null) {
          if (focus.status == MessageStatus.ok) {
            context10 = [
              '${focus.outgoing ? 'reporter' : 'reported'}: ${focus.body}',
            ];
          }
        } else if (input.include && chatId != null) {
          final msgs = await session.chat.watchMessages(chatId).first;
          final tail = msgs.length > 10 ? msgs.sublist(msgs.length - 10) : msgs;
          context10 = [
            for (final m in tail)
              if (m.status == MessageStatus.ok)
                '${m.outgoing ? 'reporter' : 'reported'}: ${m.body}',
          ];
        }
        checkAccount();
        await session.safety.report(
          peerUid: peerUid,
          reason: input.reason,
          chatId: chatId,
          note: input.note,
          context: context10,
        );
      },
    ),
  );
  if (sent == true && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Report sent. Thank you.')));
  }
  return sent == true;
}

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

class BlockedUsersScreen extends ConsumerWidget {
  const BlockedUsersScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(blockedUidsProvider);
    return Scaffold(
      appBar: UiAppBar(context: context, title: const Text('Blocked people')),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => UiEmptyState(
          title: 'Could not load blocked people',
          message: 'Try again to see your blocked contacts.',
          action: TextButton(
            onPressed: () => ref.invalidate(blockedUidsProvider),
            child: const Text('Try again'),
          ),
        ),
        data: (blocked) => blocked.isEmpty
            ? const UiEmptyState(
                title: 'No blocked people',
                message: 'You can block someone from their chat or a message request.',
                icon: Icons.block,
              )
            : UiPageScroll(
                children: [for (final uid in blocked) _BlockedTile(uid: uid)],
              ),
      ),
    );
  }
}

class _BlockedTile extends ConsumerStatefulWidget {
  const _BlockedTile({required this.uid});
  final String uid;
  @override
  ConsumerState<_BlockedTile> createState() => _BlockedTileState();
}

class _BlockedTileState extends ConsumerState<_BlockedTile> {
  bool _busy = false;
  String? _error;
  Future<void> _unblock() async {
    final session = ref.read(appSessionProvider).value;
    if (_busy || session == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await session.safety.unblock(widget.uid);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not unblock this person. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = ref.watch(peerUsernameProvider(widget.uid)).value ?? '…';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          key: Key('blocked_${widget.uid}'),
          leading: const Icon(Icons.block),
          title: Text('@$name'),
          subtitle: _busy ? const Text('Unblocking…') : null,
          trailing: TextButton(
            key: Key('unblock_${widget.uid}'),
            onPressed: _busy ? null : _unblock,
            child: const Text('Unblock'),
          ),
        ),
        if (_error != null) UiActionError(message: _error!),
      ],
    );
  }
}

class _ReportInput {
  _ReportInput(this.reason, this.note, this.include);
  final ReportReason reason;
  final String note;
  final bool include;
}

/// Owns its text controller so it is disposed only after the dialog is gone.
class _ReportDialog extends StatefulWidget {
  const _ReportDialog({
    required this.name,
    required this.canIncludeChat,
    required this.submit,
    this.aboutMessage = false,
  });
  final bool aboutMessage;
  final Future<void> Function(_ReportInput) submit;
  final String name;
  final bool canIncludeChat;
  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final _note = TextEditingController();
  var _reason = ReportReason.spam;
  var _include = false;
  bool _busy = false;
  String? _error;
  Future<void> _send() async {
    if (_busy) return;
    final input = _ReportInput(_reason, _note.text, _include);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.submit(input);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not send the report. Your choices are kept here. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: UiDialog(
      title: Text('Report @${widget.name}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RadioGroup<ReportReason>(
              groupValue: _reason,
              onChanged: (v) {
                if (!_busy) setState(() => _reason = v ?? _reason);
              },
              child: Column(
                children: [
                  for (final r in ReportReason.values)
                    RadioListTile<ReportReason>(
                      key: Key('reason_${r.name}'),
                      enabled: !_busy,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: r,
                      title: Text(_reasonLabel(r)),
                    ),
                ],
              ),
            ),
            TextField(
              key: Key('reportNote'),
              controller: _note,
              enabled: !_busy,
              maxLength: 500,
              maxLines: 3,
              decoration: InputDecoration(labelText: 'Details (optional)'),
            ),
            if (widget.canIncludeChat)
              CheckboxListTile(
                key: Key('reportInclude'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _include,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _include = v ?? false),
                title: Text(
                  widget.aboutMessage
                      ? 'Include this message'
                      : 'Include up to 10 recent readable messages',
                ),
                subtitle: FireplaceBrandText(
                  widget.aboutMessage
                      ? 'If ticked, this message is shared as text with the Fireplace team. This option starts off.'
                      : 'If ticked, selected readable messages are shared as text with the Fireplace team. This option starts off.',
                ),
              ),
            if (_error != null)
              UiActionError(key: const Key('reportError'), message: _error!),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text('Cancel'),
        ),
        TextButton(
          key: Key('sendReport'),
          onPressed: _busy ? null : _send,
          child: Text(_busy ? 'Sending…' : 'Send report'),
        ),
      ],
    ),
  );
}
