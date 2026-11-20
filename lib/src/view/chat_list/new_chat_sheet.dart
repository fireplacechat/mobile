import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/group_providers.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/account/auth_service.dart';
import 'package:fireplace/src/model/chat/chat_service.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/widgets/avatar.dart';
import 'package:fireplace/src/widgets/round_bubble_icon.dart';

/// What the person chose in [NewChatSheet].
sealed class NewChatChoice {
  const NewChatChoice();
}

/// Open this 1:1 chat (an existing one, or one just started).
class OpenChat extends NewChatChoice {
  const OpenChat(this.chatId);
  final String chatId;
}

/// Go on to name a new group and pick its people.
class CreateGroup extends NewChatChoice {
  const CreateGroup();
}

/// The panel behind the New chat button: a "To:" field, *Create group*, and
/// the people you already chat with. Typing filters the list; a username that
/// is not in it can be messaged directly.
///
/// It can be dragged down to close (issue 239): it follows the finger and
/// shows the chat list behind it, a short drag settles back, and a list
/// scrolled down first scrolls back to the top.
class NewChatSheet extends ConsumerStatefulWidget {
  const NewChatSheet({super.key});

  static Future<NewChatChoice?> show(BuildContext context) =>
      showModalBottomSheet<NewChatChoice>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: false,
        // The panel paints itself, so its background moves with the drag.
        backgroundColor: Colors.transparent,
        elevation: 0,
        builder: (_) => const NewChatSheet(),
      );

  @override
  ConsumerState<NewChatSheet> createState() => _NewChatSheetState();
}

class _NewChatSheetState extends ConsumerState<NewChatSheet> {
  final _to = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _to.dispose();
    super.dispose();
  }

  String get _query => _to.text.trim().toLowerCase();

  /// Starts a chat with a username typed in the To: field.
  Future<void> _start(String name) async {
    if (_busy) return;
    if (name.isEmpty) {
      setState(() => _error = 'Enter a username.');
      return;
    }
    if (!AuthService.isValidUsername(name)) {
      setState(() => _error = 'Use 3–20 letters, numbers or underscores.');
      return;
    }
    final session = ref.read(appSessionProvider).value;
    if (session == null) {
      setState(() => _error = 'Your account is not ready yet.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await session.chat.startChat(name);
      if (mounted) Navigator.pop(context, OpenChat(id));
    } on ChatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not start chat. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static const _toStyle = TextStyle(fontSize: 16, height: 1.25);
  static OutlineInputBorder _pill(BorderSide side) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(999),
    borderSide: side,
  );

  @override
  Widget build(BuildContext context) {
    final t = FireplaceUiTokens.of(context);
    final me = ref.watch(appSessionProvider).value?.uid ?? '';
    final blocked = ref.watch(blockedUidsProvider).value ?? const <String>{};
    final groupsOn = ref.watch(groupsOnProvider);
    final chats =
        [
          for (final c
              in ref.watch(chatsProvider).value ?? const <ChatSummary>[])
            if (!c.isIncomingRequest(me) && !blocked.contains(c.peerUid)) c,
        ]..sort(
          (a, b) => (b.lastMessageAt ?? DateTime(0)).compareTo(
            a.lastMessageAt ?? DateTime(0),
          ),
        );
    String? nameOf(ChatSummary c) =>
        ref.watch(peerUsernameProvider(c.peerUid)).value;
    final shown = [
      for (final c in chats)
        if (_query.isEmpty ||
            (nameOf(c)?.toLowerCase().contains(_query) ?? false))
          c,
    ];
    final exact = chats
        .where((c) => nameOf(c)?.toLowerCase() == _query)
        .firstOrNull;
    final typed = _to.text.trim();
    final canMessage = exact == null && AuthService.isValidUsername(typed);
    final sheet = Theme.of(context).bottomSheetTheme;
    final background =
        sheet.modalBackgroundColor ??
        sheet.backgroundColor ??
        Theme.of(context).colorScheme.surfaceContainerLow;
    return LayoutBuilder(
      builder: (context, outer) => DraggableScrollableSheet(
        initialChildSize: 1,
        // Not while a chat is starting: the panel waits for the answer.
        minChildSize: _busy ? 1 : 0,
        snap: true,
        builder: (context, scroll) => Material(
          color: background,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          clipBehavior: Clip.antiAlias,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topCenter,
              minHeight: outer.maxHeight,
              maxHeight: outer.maxHeight,
              child: _content(
                context,
                t,
                chats,
                shown,
                canMessage,
                typed,
                groupsOn,
                scroll,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    FireplaceUiTokens t,
    List<ChatSummary> chats,
    List<ChatSummary> shown,
    bool canMessage,
    String typed,
    bool groupsOn,
    ScrollController scroll,
  ) {
    return SizedBox(
      height: double.infinity,
      child: Column(
        children: [
          SizedBox(
            height: 56,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  'New chat',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                // Closing is an x in a grey circle, top right.
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: IconButton(
                      key: const Key('cancelNewChat'),
                      tooltip: 'Close',
                      style: IconButton.styleFrom(
                        minimumSize: const Size(32, 32),
                        fixedSize: const Size(32, 32),
                        padding: EdgeInsets.zero,
                        backgroundColor: t.selectedRow,
                        foregroundColor: t.secondaryText,
                        tapTargetSize: MaterialTapTargetSize.padded,
                      ),
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              key: const Key('peerUsername'),
              controller: _to,
              enabled: !_busy,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.go,
              // The same text as the search field of the chat list.
              style: _toStyle,
              decoration: InputDecoration(
                isDense: true,
                // Always shown, unlike prefixText, which needs focus.
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(left: 18, right: 8),
                  child: Text(
                    'To:',
                    style: _toStyle.copyWith(color: t.secondaryText),
                  ),
                ),
                prefixIconConstraints: const BoxConstraints(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                hintText: 'Username',
                hintStyle: _toStyle.copyWith(color: t.secondaryText),
                // A pill, like the search field; red all round when the
                // name is not one that can be messaged.
                border: _pill(BorderSide.none),
                enabledBorder: _pill(BorderSide.none),
                focusedBorder: _pill(BorderSide(color: t.accent)),
                errorBorder: _pill(BorderSide(color: t.danger, width: 2)),
                focusedErrorBorder: _pill(
                  BorderSide(color: t.danger, width: 2),
                ),
                errorText: _error,
                errorMaxLines: 3,
              ),
              onChanged: (_) => setState(() => _error = null),
              // Reads the field now, not the text of the last build.
              onSubmitted: (value) {
                final name = value.trim();
                final match = chats
                    .where(
                      (c) =>
                          ref
                              .read(peerUsernameProvider(c.peerUid))
                              .value
                              ?.toLowerCase() ==
                          name.toLowerCase(),
                    )
                    .firstOrNull;
                if (match != null) {
                  Navigator.pop(context, OpenChat(match.chatId));
                } else {
                  _start(name);
                }
              },
            ),
          ),
          Divider(height: 1, color: t.separator),
          Expanded(
            child: ListView(
              key: const Key('newChatList'),
              controller: scroll,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                if (groupsOn && _query.isEmpty)
                  ListTile(
                    key: const Key('newGroup'),
                    leading: CircleAvatar(
                      radius: 22,
                      backgroundColor: t.panel,
                      foregroundColor: t.text,
                      child: const Icon(Icons.groups_outlined),
                    ),
                    title: const Text(
                      'Create group',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    trailing: Icon(Icons.chevron_right, color: t.secondaryText),
                    onTap: () => Navigator.pop(context, const CreateGroup()),
                  ),
                if (canMessage)
                  ListTile(
                    key: const Key('startChat'),
                    enabled: !_busy,
                    leading: CircleAvatar(
                      radius: 22,
                      backgroundColor: t.accent,
                      foregroundColor: Colors.white,
                      child: _busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(roundBubble),
                    ),
                    title: Text('Message @$typed'),
                    subtitle: Text(
                      _busy ? 'Starting…' : 'Send a message request',
                    ),
                    onTap: () => _start(typed),
                  ),
                for (final c in shown)
                  _ContactRow(
                    chat: c,
                    onTap: _busy
                        ? null
                        : () => Navigator.pop(context, OpenChat(c.chatId)),
                  ),
                if (shown.isEmpty && !canMessage && _query.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No one you chat with is called that.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: t.secondaryText),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One person you already chat with.
class _ContactRow extends ConsumerWidget {
  const _ContactRow({required this.chat, required this.onTap});
  final ChatSummary chat;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(peerUsernameProvider(chat.peerUid)).value ?? '…';
    return ListTile(
      key: Key('contact_${chat.peerUid}'),
      leading: PersonAvatar(name: name),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: chat.accepted
          ? null
          : Text(
              'Request sent',
              style: TextStyle(
                color: FireplaceUiTokens.of(context).secondaryText,
              ),
            ),
      onTap: onTap,
    );
  }
}
