import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/group_providers.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/groups/group_models.dart';
import 'package:fireplace/src/view/groups/group_chat_screen.dart';
import 'package:fireplace/src/view/groups/group_tile.dart';
import 'package:fireplace/src/view/groups/new_group_screen.dart';
import 'package:fireplace/src/model/chat/chat_preview.dart';
import 'package:fireplace/src/model/chat/chat_summary.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:fireplace/src/styles/brand/logo.dart';
import 'package:fireplace/src/styles/brand/lockup.dart';
import 'package:fireplace/src/view/safety/requests_screen.dart';
import 'package:fireplace/src/view/invites/invite_screen.dart';
import 'package:fireplace/src/view/settings/settings_screen.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/view/search/message_search_results.dart';
import 'package:fireplace/src/widgets/app_bar.dart';
import 'package:fireplace/src/widgets/page.dart';
import 'package:fireplace/src/view/chat_list/new_chat_sheet.dart';
import 'package:fireplace/src/view/chat_list/widgets/chat_search_field.dart';
import 'package:fireplace/src/view/chat_list/widgets/chat_tile.dart';
import 'package:fireplace/src/view/chat_list/widgets/new_chat_icon.dart';

class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key});

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  String _query = '';
  final _search = TextEditingController();
  bool _opening = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _open(Widget screen) async {
    if (_opening) return;
    _opening = true;
    try {
      await Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => screen));
    } finally {
      _opening = false;
    }
  }

  /// The invite page slides in from the left, the side its button is on.
  Future<void> _openInvites() async {
    if (_opening) return;
    _opening = true;
    try {
      await Navigator.of(context).push(InviteScreen.route());
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final chats = ref.watch(chatsProvider);
    // Shares a new primary colour with your groups when it changes.
    ref.watch(groupColorSyncProvider);
    return Scaffold(
      appBar: UiAppBar(
        context: context,
        centerTitle: true,
        leadingWidth: 64,
        leading: Center(
          child: IconButton(
            key: const Key('inviteFriends'),
            tooltip: 'Invite friends',
            onPressed: () => _openInvites(),
            style: IconButton.styleFrom(
              backgroundColor: FireplaceUiTokens.of(context).accent,
              foregroundColor: Colors.white,
              // A 40 px circle; the tap target stays 48 px.
              fixedSize: const Size.square(40),
              minimumSize: const Size.square(40),
            ),
            icon: const Icon(Icons.add_rounded),
          ),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FireplaceLogo(size: 30),
            SizedBox(width: 10),
            Flexible(child: FireplaceWordmark(height: 24)),
          ],
        ),
        actions: [
          IconButton(
            key: Key('settings'),
            tooltip: 'Settings',
            icon: Icon(Icons.settings_outlined),
            onPressed: () => _open(const SettingsScreen()),
          ),
        ],
      ),
      floatingActionButton: SizedBox.square(
        dimension: 50,
        child: FloatingActionButton(
          key: const Key('newChat'),
          tooltip: 'New chat',
          shape: const CircleBorder(),
          onPressed: () => _newChat(context, ref),
          child: Semantics(label: 'New chat', child: const NewChatIcon()),
        ),
      ),
      body: UiBodyViewport(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: ChatSearchField(
                controller: _search,
                onChanged: (value) =>
                    setState(() => _query = value.trim().toLowerCase()),
              ),
            ),
            Expanded(
              child: chats.when(
                loading: () => Center(child: CircularProgressIndicator()),
                error: (e, _) => UiEmptyState(
                  title: 'Could not load chats',
                  message: 'Try again to load your conversations.',
                  action: TextButton(
                    onPressed: () => ref.invalidate(chatsProvider),
                    child: Text('Try again'),
                  ),
                ),
                data: (list) {
                  final blocks = ref.watch(blockedUidsProvider);
                  final hides = ref.watch(hiddenChatsProvider);
                  if (blocks.isLoading || hides.isLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!blocks.hasValue ||
                      !hides.hasValue ||
                      blocks.hasError ||
                      hides.hasError) {
                    return UiEmptyState(
                      title: 'Could not load privacy settings',
                      message: 'Your conversations stay hidden until these settings are available.',
                      action: TextButton(
                        onPressed: () {
                          ref.invalidate(blockedUidsProvider);
                          ref.invalidate(hiddenChatsProvider);
                        },
                        child: const Text('Try again'),
                      ),
                    );
                  }
                  final session = ref.watch(appSessionProvider).value;
                  final me = session?.uid ?? '';
                  final blocked =
                      ref.watch(blockedUidsProvider).value ?? const <String>{};
                  final hidden =
                      ref.watch(hiddenChatsProvider).value ?? const <String>{};
                  final live = [
                    for (final c in list)
                      if (!blocked.contains(c.peerUid) &&
                          !hidden.contains(c.chatId))
                        c,
                  ];
                  final requests = [
                    for (final c in live)
                      if (c.isIncomingRequest(me)) c,
                  ];
                  // Group invitations wait in Message requests too.
                  final invitations =
                      ref.watch(groupInvitationsProvider).value ?? const [];
                  final requestCount = requests.length + invitations.length;
                  final groups = [
                    for (final g
                        in (ref.watch(groupsProvider).value ?? const {}).values)
                      if (_query.isEmpty ||
                          g.name.toLowerCase().contains(_query))
                        g,
                  ];
                  // Newest first, by the newest message this phone knows of: a
                  // message just sent or received moves its chat up at once.
                  final epoch = DateTime.fromMillisecondsSinceEpoch(0);
                  final activity = {
                    for (final c in live)
                      c.chatId:
                          latestActivity(
                            c.lastMessageAt,
                            ref.watch(chatPreviewProvider(c.chatId)),
                          ) ??
                          epoch,
                  };
                  final sorted =
                      [
                        for (final c in live)
                          if (!c.isIncomingRequest(me) &&
                              (_query.isEmpty ||
                                  (ref
                                          .watch(
                                            peerUsernameProvider(c.peerUid),
                                          )
                                          .value
                                          ?.toLowerCase()
                                          .contains(_query) ??
                                      false)))
                            c,
                      ]..sort(
                        (a, b) =>
                            activity[b.chatId]!.compareTo(activity[a.chatId]!),
                      );
                  final namesPending =
                      _query.isNotEmpty &&
                      live.any(
                        (c) =>
                            !c.isIncomingRequest(me) &&
                            ref
                                .watch(peerUsernameProvider(c.peerUid))
                                .isLoading,
                      );
                  final emptyTitle = namesPending
                      ? 'Looking up usernames'
                      : 'No conversations found';
                  final emptyMessage = namesPending
                      ? 'Some usernames are still loading. Results will appear here.'
                      : 'Try another username.';
                  if (_query.isNotEmpty) {
                    return ListView(
                      key: const Key('globalSearchResults'),
                      padding: const EdgeInsets.only(bottom: 96),
                      children: [
                        if (requestCount > 0)
                          ListTile(
                            key: const Key('requestsTile'),
                            leading: const Icon(
                              Icons.mark_email_unread_outlined,
                            ),
                            title: Text('Message requests ($requestCount)'),
                            subtitle: const Text(
                              'People who want to chat with you',
                            ),
                            onTap: () => _open(const RequestsScreen()),
                          ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          child: Text(
                            'People',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (sorted.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              namesPending
                                  ? 'Looking up usernames'
                                  : 'No conversations found',
                            ),
                          ),
                        for (final chat in sorted)
                          ChatTile(
                            chat: chat,
                            onOpen: () =>
                                _open(ChatScreen(chatId: chat.chatId)),
                          ),
                        if (groups.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                            child: Text(
                              'Groups',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        for (final g in groups)
                          GroupTile(
                            group: g,
                            onOpen: () => _open(GroupChatScreen(gid: g.gid)),
                          ),
                        GlobalMessageResults(query: _query, onOpen: _open),
                      ],
                    );
                  }
                  // Chats and groups together, newest activity first.
                  final groupActivity = {
                    for (final g in groups)
                      g.gid:
                          (ref
                              .watch(groupMessagesProvider(g.gid))
                              .value
                              ?.lastOrNull
                              ?.sentAt) ??
                          epoch,
                  };
                  final entries = <Object>[...sorted, ...groups]
                    ..sort((a, b) {
                      DateTime at(Object e) => e is GroupInfo
                          ? groupActivity[e.gid]!
                          : activity[(e as ChatSummary).chatId]!;
                      return at(b).compareTo(at(a));
                    });
                  if (entries.isEmpty && requestCount == 0) {
                    if (_query.isNotEmpty) {
                      return UiEmptyState(
                        title: emptyTitle,
                        message: emptyMessage,
                      );
                    }
                    return _Empty();
                  }
                  final requestOffset = requestCount == 0 ? 0 : 1;
                  return ListView.separated(
                    key: const Key('conversationList'),
                    padding: const EdgeInsets.only(bottom: 96),
                    itemCount:
                        entries.length +
                        requestOffset +
                        (entries.isEmpty ? 1 : 0),
                    // A hairline from the text edge to the row's end.
                    separatorBuilder: (_, _) => const Divider(
                      height: 1 / 3,
                      thickness: 1 / 3,
                      indent: ChatTile.textInset,
                      endIndent: ChatTile.edge,
                    ),
                    itemBuilder: (_, i) {
                      if (requestCount > 0 && i == 0) {
                        return ListTile(
                          key: Key('requestsTile'),
                          leading: CircleAvatar(
                            backgroundColor: FireplaceUiTokens.of(context)
                                .accent,
                            foregroundColor: Theme.of(context)
                                .colorScheme
                                .onPrimary,
                            child: Icon(Icons.mark_email_unread_outlined),
                          ),
                          title: Text(
                            'Message requests ($requestCount)',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text('People who want to chat with you'),
                          trailing: Icon(Icons.chevron_right),
                          onTap: () => _open(const RequestsScreen()),
                        );
                      }
                      if (entries.isEmpty) {
                        return _query.isEmpty
                            ? const UiEmptyState(
                                title: 'No conversations yet',
                                message: 'Accept a request above, or choose New chat to start a conversation.',
                              )
                            : const UiEmptyState(
                                title: 'No conversations found',
                                message: 'Try another username. Your message requests are shown above.',
                              );
                      }
                      final entry = entries[i - requestOffset];
                      if (entry is GroupInfo) {
                        return GroupTile(
                          group: entry,
                          onOpen: () => _open(GroupChatScreen(gid: entry.gid)),
                        );
                      }
                      final chat = entry as ChatSummary;
                      return ChatTile(
                        chat: chat,
                        onOpen: () => _open(ChatScreen(chatId: chat.chatId)),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// New chat: a panel to pick someone you chat with, type a username, or
  /// create a group.
  Future<void> _newChat(BuildContext context, WidgetRef ref) async {
    if (_opening) return;
    final choice = await NewChatSheet.show(context);
    if (choice == null || !context.mounted) return;
    switch (choice) {
      case OpenChat(:final chatId):
        await _open(ChatScreen(chatId: chatId));
      case CreateGroup():
        final gid = await Navigator.of(context).push<String>(
          MaterialPageRoute(builder: (_) => const NewGroupScreen()),
        );
        if (gid != null && context.mounted) {
          await _open(GroupChatScreen(gid: gid));
        }
    }
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) => const UiEmptyState(
    title: 'Your conversations start here',
    message: 'Choose New chat and enter a friend’s username. Messages are end-to-end encrypted.',
  );
}
