import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/view/chat/chat_screen.dart';
import 'package:fireplace/src/styles/brand/logo.dart';
import 'package:fireplace/src/styles/brand/lockup.dart';
import 'package:fireplace/src/view/safety/requests_screen.dart';
import 'package:fireplace/src/ui/settings_screen.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/view/search/message_search_results.dart';
import 'package:fireplace/src/widgets/app_bar.dart';
import 'package:fireplace/src/widgets/page.dart';
import 'package:fireplace/src/view/chat_list/start_chat_dialog.dart';
import 'package:fireplace/src/view/chat_list/widgets/chat_tile.dart';

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

  @override
  Widget build(BuildContext context) {
    final chats = ref.watch(chatsProvider);
    return Scaffold(
      appBar: UiAppBar(
        context: context,
        title: Row(
          children: [
            FireplaceLogo(size: 30),
            SizedBox(width: 10),
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: FireplaceWordmark(height: 24),
              ),
            ),
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
      floatingActionButton: FloatingActionButton.extended(
        key: Key('newChat'),
        onPressed: () => _newChat(context, ref),
        icon: Icon(Icons.edit_outlined),
        label: Text('New chat'),
      ),
      body: UiBodyViewport(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: TextField(
                key: Key('chatSearch'),
                controller: _search,
                decoration: InputDecoration(
                  hintText: 'Search people and messages',
                  prefixIcon: Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          key: const Key('clearChatSearch'),
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
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
                            (b.lastMessageAt ??
                                    DateTime.fromMillisecondsSinceEpoch(0))
                                .compareTo(
                                  a.lastMessageAt ??
                                      DateTime.fromMillisecondsSinceEpoch(0),
                                ),
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
                        if (requests.isNotEmpty)
                          ListTile(
                            key: const Key('requestsTile'),
                            leading: const Icon(
                              Icons.mark_email_unread_outlined,
                            ),
                            title: Text(
                              'Message requests (${requests.length})',
                            ),
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
                        GlobalMessageResults(query: _query, onOpen: _open),
                      ],
                    );
                  }
                  if (sorted.isEmpty && requests.isEmpty) {
                    if (_query.isNotEmpty) {
                      return UiEmptyState(
                        title: emptyTitle,
                        message: emptyMessage,
                      );
                    }
                    return _Empty();
                  }
                  final requestOffset = requests.isEmpty ? 0 : 1;
                  return ListView.separated(
                    key: const Key('conversationList'),
                    padding: const EdgeInsets.only(bottom: 96),
                    itemCount:
                        sorted.length +
                        requestOffset +
                        (sorted.isEmpty ? 1 : 0),
                    separatorBuilder: (_, _) => Divider(height: 1, indent: 72),
                    itemBuilder: (_, i) {
                      if (requests.isNotEmpty && i == 0) {
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
                            'Message requests (${requests.length})',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text('People who want to chat with you'),
                          trailing: Icon(Icons.chevron_right),
                          onTap: () => _open(const RequestsScreen()),
                        );
                      }
                      if (sorted.isEmpty) {
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
                      final chat = sorted[i - requestOffset];
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

  Future<void> _newChat(BuildContext context, WidgetRef ref) async {
    if (_opening) return;
    _opening = true;
    try {
      final chatId = await showDialog<String>(
        context: context,
        builder: (_) => const StartChatDialog(),
      );
      if (chatId == null || !context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => ChatScreen(chatId: chatId)),
      );
    } finally {
      _opening = false;
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
