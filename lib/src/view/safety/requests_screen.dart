import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/group_providers.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/view/groups/group_invitation_card.dart';
import 'package:fireplace/src/model/chat/chat_service.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:fireplace/src/view/safety/confirm_block.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/view/safety/request_buttons.dart';
import 'package:fireplace/src/widgets/app_bar.dart';
import 'package:fireplace/src/widgets/avatar.dart';
import 'package:fireplace/src/widgets/page.dart';
import 'package:fireplace/src/widgets/status.dart';

/// People who started a chat with you and are waiting for you to accept.
class RequestsScreen extends ConsumerWidget {
  const RequestsScreen({super.key});
  static const routeName = '/requests';

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
    final invitations = ref.watch(groupInvitationsProvider).value ?? const [];
    return Scaffold(
      appBar: UiAppBar(context: context, title: Text('Message requests')),
      body: requests.isEmpty && invitations.isEmpty
          ? const UiEmptyState(
              title: 'No message requests',
              message: 'New requests will appear here. Messages stay hidden until you accept.',
              illustration: _NobodyWaiting(),
            )
          // Rows in the chat list's own style, divided by hairlines.
          : UiPageScroll(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    'You will not see what they wrote until you accept. '
                    'They cannot see whether you have looked.',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: FireplaceUiTokens.of(context).secondaryText,
                    ),
                  ),
                ),
                for (final (i, row) in [
                  for (final g in invitations)
                    GroupInvitationCard(invitation: g, inRequests: true),
                  for (final c in requests)
                    _RequestTile(
                      key: ValueKey(c.chatId),
                      chat: c,
                      session: session!,
                    ),
                ].indexed) ...[
                  if (i > 0)
                    Divider(
                      height: 1 / 3,
                      thickness: 1 / 3,
                      indent: 16 + 52 + 12,
                      color: FireplaceUiTokens.of(context).separator,
                    ),
                  row,
                ],
              ],
            ),
    );
  }
}

/// The empty page's picture: three soft places where faces would be.
class _NobodyWaiting extends StatelessWidget {
  const _NobodyWaiting();

  @override
  Widget build(BuildContext context) {
    final t = FireplaceUiTokens.of(context);
    return SizedBox(
      width: 120,
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(left: 0, child: _Place(size: 52, fill: t.separator)),
          Positioned(right: 0, child: _Place(size: 52, fill: t.separator)),
          // Solid, so the places behind it do not show through.
          _Place(
            size: 64,
            fill: Color.alphaBlend(t.accentText.withAlpha(150), t.page),
          ),
        ],
      ),
    );
  }
}

/// One place for a face, ringed in the page colour.
class _Place extends StatelessWidget {
  const _Place({required this.size, required this.fill});
  final double size;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    final page = FireplaceUiTokens.of(context).page;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: page, width: 3),
      ),
      child: Icon(Icons.person, size: size * .55, color: page),
    );
  }
}

class _RequestTile extends ConsumerStatefulWidget {
  const _RequestTile({super.key, required this.chat, required this.session});
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
    final t = FireplaceUiTokens.of(context);
    final name = ref.watch(peerUsernameProvider(chat.peerUid)).value ?? '…';
    void openRequest() {
      final navigator = Navigator.of(context);
      final requests = ModalRoute.of(context);
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => ChatScreen(
            chatId: chat.chatId,
            onRequestAccepted: () {
              if (requests != null &&
                  requests.settings.name == RequestsScreen.routeName &&
                  requests.isActive) {
                navigator.removeRoute(requests);
              }
            },
          ),
        ),
      );
    }

    return Padding(
      key: Key('request_${chat.chatId}'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PersonAvatar(name: name, size: 52),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Who it is opens the request, where the messages wait.
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: _busy ? null : openRequest,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.25,
                          fontWeight: FontWeight.w600,
                          color: t.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'wants to chat',
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.33,
                          color: t.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      key: Key('accept_${chat.chatId}'),
                      style: RequestButtons.main(),
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                              final navigator = Navigator.of(context);
                              final requests = ModalRoute.of(context);
                              // Opened as the chat list opens a chat.
                              final conversation = MaterialPageRoute<void>(
                                builder: (_) => ChatScreen(chatId: chat.chatId),
                              );
                              await session.chat.acceptRequest(chat.chatId);
                              if (mounted) ref.invalidate(hiddenChatsProvider);
                              // The row can go before this returns, once the
                              // chat stops being a request.
                              if (navigator.mounted &&
                                  requests?.isCurrent == true) {
                                navigator.pushReplacement(conversation);
                              }
                            }),
                      child: const Text('Accept'),
                    ),
                    OutlinedButton(
                      key: Key('ignore_${chat.chatId}'),
                      style: RequestButtons.quiet(context),
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
                      style: RequestButtons.danger(context),
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
                if (_error != null) UiActionError(message: _error!),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
