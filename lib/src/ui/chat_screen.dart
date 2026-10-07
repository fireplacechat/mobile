import 'package:fireplace/src/view/chat/timeline_scroll.dart';
import 'package:fireplace/src/model/chat/contact_controller.dart';
import 'package:fireplace/src/model/chat/send_controller.dart';
import 'package:fireplace/src/view/chat/widgets/composer_note.dart';
import 'package:fireplace/src/view/chat/widgets/request_banner.dart';
import 'package:fireplace/src/view/chat/widgets/unconfirmed_note.dart';
import 'package:fireplace/src/view/chat/widgets/new_device_banner.dart';
import 'package:fireplace/src/view/chat/widgets/identity_alert_banner.dart';
import 'package:fireplace/src/model/chat/memory_pending.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/crypto/fingerprint.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/services/chat_service.dart';
import 'package:fireplace/src/ui/safety_ui.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/ui/presentation.dart';
import 'package:fireplace/src/view/safety/verify_screen.dart';
import 'package:fireplace/src/view/chat/chat_details_screen.dart';
import 'package:fireplace/src/ui/chat_activity.dart';
import 'package:fireplace/src/view/chat/forward/forward_message.dart';
import 'package:fireplace/src/model/chat/message_format.dart';
import 'package:fireplace/src/view/chat/message_actions.dart';
import 'package:fireplace/src/model/chat/pending_sends.dart';
import 'package:fireplace/src/model/chat/message_limits.dart';
import 'package:fireplace/src/view/chat/composer/message_input_formatter.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.chatId, this.initialMessageId});
  final String chatId;
  final String? initialMessageId;
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with RouteAware, WidgetsBindingObserver {
  ModalRoute<void>? _route;
  String? _ownerUid;
  late final ChatVisibility _visibilityNotifier;
  bool _showAll = false;
  bool _foreground = true;
  final _text = TextEditingController();
  late final SendController _sendController;
  late final TimelineScroll _timeline;
  int _draftRevision = 0;
  String _lastDraftText = '';

  late final ContactController _contactController;
  @override
  void initState() {
    super.initState();
    _contactController =
        ContactController(
          reviewOnce: (peerUid, pub) async {
            final session = ref.read(appSessionProvider).value;
            if (session != null) {
              await _reviewIdentityOnce(session, peerUid, pub);
            }
          },
        )..addListener(() {
          if (mounted) setState(() {});
        });
    _sendController =
        SendController(
          chatId: () => widget.chatId,
          chat: () => ref.read(appSessionProvider).value?.chat,
          ownerUid: () => ref.read(appSessionProvider).value?.uid,
          pendingSends: () => ref.read(pendingLocalSendsProvider.notifier),
          draft: () => _text.text,
          draftRevision: () => _draftRevision,
          clearDraft: () => _text.clear(),
          notice: _snack,
          showNewest: () => _timeline.showNewestAfterOwnSend(_latest),
          reviewIdentity: (peerUid, pub) =>
              _contactController.reviewIdentity(peerUid, pub),
          identityAlerts: () => ref.read(identityAlertsProvider).value ?? {},
          confirmSendAnotherCopy: _confirmSendAnotherCopy,
        )..addListener(() {
          if (mounted) setState(() {});
        });
    _visibilityNotifier = ref.read(visibleChatProvider.notifier);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _text.addListener(_onDraftChanged);
    _timeline = TimelineScroll(isMounted: () => mounted)
      ..addListener(() {
        if (mounted) setState(() {});
      });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _route && route is ModalRoute<void>) {
      chatRouteObserver.unsubscribe(this);
      _route = route;
      chatRouteObserver.subscribe(this, route);
    }
  }

  void _visibility() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _visibilityNotifier.clearIf(widget.chatId);
        return;
      }
      final visible = _foreground && (_route?.isCurrent ?? false);
      final notifier = _visibilityNotifier;
      if (visible) {
        notifier.show(widget.chatId);
        _markSeen();
      } else if (ref.read(visibleChatProvider) == widget.chatId) {
        notifier.show(null);
      }
    });
  }

  @override
  void didPush() => _visibility();
  @override
  void didPushNext() => _visibility();
  @override
  void didPopNext() => _visibility();
  @override
  void didPop() => _visibility();
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _visibility();
  }

  void _markSeen() {
    if (!_foreground ||
        !(_route?.isCurrent ?? false) ||
        !ref.read(chatActivityProvider).preferencesAvailable) {
      return;
    }
    final summary = ref.read(chatSummaryProvider(widget.chatId));
    final activity = ref.read(chatActivityProvider.notifier);
    if (summary == null || !activity.eligible(summary)) return;
    final messages = ref.read(messagesProvider(widget.chatId)).value ?? [];
    final index = !_showAll && widget.initialMessageId != null
        ? messages.indexWhere((m) => m.id == widget.initialMessageId)
        : -1;
    activity
        .seen(widget.chatId, index < 0 ? messages : messages.take(index + 1))
        .catchError((Object _) {
          if (mounted) {
            _snack('Could not save the unread count on this device.');
          }
        });
  }

  Future<void> _mute(bool value) async {
    try {
      await ref.read(chatActivityProvider.notifier).mute(widget.chatId, value);
    } catch (_) {
      if (mounted) _snack('Could not save the mute preference. Try again.');
    }
  }

  /// The long-press menu for one message. Add reply/delete/react here later.
  List<MessageAction> _actionsFor(
    LocalMessage message, {
    required String name,
    required String? peerUid,
    required bool blocked,
    required bool incomingRequest,
    required bool identityHeld,
  }) {
    final owner = ref.read(appSessionProvider).value;
    bool available() {
      if (!mounted || owner == null) return false;
      final summary = ref.read(chatSummaryProvider(widget.chatId));
      return identical(ref.read(appSessionProvider).value, owner) &&
          summary != null &&
          ref.read(chatActivityProvider.notifier).eligible(summary);
    }

    void run(VoidCallback action) {
      if (available()) action();
    }

    final readable = message.status != MessageStatus.undecryptable;
    final canShare = !incomingRequest && !identityHeld && !blocked && readable;
    return [
      if (canShare)
        MessageAction(
          id: 'copy',
          label: 'Copy',
          icon: Icons.copy_outlined,
          onSelected: () => run(() => _copyMessage(message)),
        ),
      if (canShare &&
          !messageTooLong(message.body) &&
          message.status == MessageStatus.ok)
        MessageAction(
          id: 'forward',
          label: 'Forward',
          icon: Icons.forward_outlined,
          onSelected: () => run(() => forwardMessage(context, message, name)),
        ),
      if (canShare)
        MessageAction(
          id: 'selectText',
          label: 'Select text',
          icon: Icons.text_fields_outlined,
          onSelected: () => run(
            () => showSelectTextSheet(
              context,
              displayMessage(message.body).plain,
              protectSelection: (ctx, child) => Consumer(
                builder: (ctx, sheetRef, _) {
                  sheetRef.watch(appSessionProvider);
                  sheetRef.watch(chatsProvider);
                  sheetRef.watch(blockedUidsProvider);
                  sheetRef.watch(hiddenChatsProvider);
                  sheetRef.watch(identityAlertsProvider);
                  return available()
                      ? child
                      : const Text(
                          'This conversation is no longer available. Close this sheet and return to your chats.',
                        );
                },
              ),
            ),
          ),
        ),
      // Only another person's message can be reported.
      if (!message.outgoing &&
          peerUid != null &&
          !incomingRequest &&
          !identityHeld &&
          !blocked)
        MessageAction(
          id: 'report',
          label: 'Report',
          icon: Icons.flag_outlined,
          destructive: true,
          onSelected: () => run(
            () => _contactController.contactAction(() async {
              await showReportDialog(
                context,
                ref,
                peerUid: peerUid,
                name: name,
                chatId: widget.chatId,
                focus: message,
              );
            }),
          ),
        ),
    ];
  }

  Future<void> _copyMessage(LocalMessage message) async {
    try {
      await Clipboard.setData(
        ClipboardData(text: displayMessage(message.body).plain),
      );
      if (mounted) _snack('Message copied');
    } catch (_) {
      if (mounted) _snack('Could not copy this message. Try again.');
    }
  }

  void _onDraftChanged() {
    if (_text.text == _lastDraftText) return;
    _lastDraftText = _text.text;
    _draftRevision++;
    if (mounted) setState(() {});
  }

  void _latest() {
    if (!_showAll && widget.initialMessageId != null) {
      setState(() => _showAll = true);
    }
    _timeline.scrollToLatest(
      reduceMotion: MediaQuery.disableAnimationsOf(context),
    );
  }

  @override
  void dispose() {
    chatRouteObserver.unsubscribe(this);
    final id = widget.chatId;
    final visibility = _visibilityNotifier;
    WidgetsBinding.instance.addPostFrameCallback((_) => visibility.clearIf(id));
    WidgetsBinding.instance.removeObserver(this);
    _text.removeListener(_onDraftChanged);
    _text.dispose();
    _timeline.dispose();
    _sendController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  Future<bool?> _confirmSendAnotherCopy() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => UiDialog(
        title: const Text('Send another copy?'),
        content: const SingleChildScrollView(
          child: Text(
            'The original may already have been delivered. This sends a new message.',
          ),
        ),
        actions: [
          TextButton(
            key: const Key('cancelResend'),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('confirmResend'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send another copy'),
          ),
        ],
      ),
    );
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _reviewIdentityOnce(
    AppSession session,
    String peerUid,
    List<int> newIdentityPub,
  ) async {
    final newFp = await identityFingerprint(newIdentityPub);
    final oldPin = await session.keys.pinnedIdentity(peerUid);
    final oldFp = oldPin == null ? null : await identityFingerprint(oldPin);
    if (!mounted) return;
    final trust = await showDialog<bool>(
      context: context,
      builder: (ctx) => UiDialog(
        icon: Icon(
          Icons.warning_amber_rounded,
          color: FireplaceUiTokens.of(context).danger,
          size: 40,
        ),
        title: Text('Security code changed'),
        content: SingleChildScrollView(
          child: Text(
            "This contact's identity key is different from the one you saw "
            'before. That can happen if they reinstalled the app or lost '
            'their phone, but it can also mean someone is interfering. '
            'Messages to and from them are on hold.\n\n'
            '${oldFp == null ? '' : 'Previous key:\n$oldFp\n\n'}'
            'New key:\n$newFp\n\n'
            'Ask them (in person or over a call you trust) to read you the '
            'fingerprint under Settings, and only trust the new key if it '
            'matches.',
          ),
        ),
        actions: [
          TextButton(
            key: Key('keepBlocked'),
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Keep on hold'),
          ),
          TextButton(
            key: Key('trustNew'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Trust new key',
              style: TextStyle(color: FireplaceUiTokens.of(context).danger),
            ),
          ),
        ],
      ),
    );
    if (trust == true) {
      await session.keys.acceptIdentityChange(peerUid, newIdentityPub);
      await session.chat.retryDeferred(); // delivers what was held back
      _snack('New key trusted.');
    }
  }

  Future<void> _blockPeer(
    AppSession session,
    String peerUid,
    String name,
  ) async {
    if (!await confirmBlock(context, name) || !mounted) return;
    await session.safety.block(peerUid);
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  bool _sameAccount(AppSession? session) =>
      session != null && (_ownerUid == null || _ownerUid == session.uid);

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(appSessionProvider);
    final session = account.value;
    if (account.isLoading || account.hasError || !_sameAccount(session)) {
      if (session?.uid != _ownerUid) {
        _sendController.clearMemoryPending();
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && session?.uid != _ownerUid && _text.text.isNotEmpty) {
          _text.clear();
        }
      });
      return Scaffold(
        appBar: UiAppBar(
          context: context,
          title: const Text('Conversation unavailable'),
        ),
        body: UiEmptyState(
          title: 'Return to your chats',
          message: 'Your account changed or is not ready. Open the conversation again from your chat list.',
          action: TextButton(
            onPressed: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
            child: const Text('Return to chats'),
          ),
        ),
      );
    }
    _ownerUid ??= session?.uid;
    final peerUid = session?.chat.peerOf(widget.chatId);
    final name = peerUid == null
        ? ''
        : ref.watch(peerUsernameProvider(peerUid)).value ?? '';
    final messageState = ref.watch(messagesProvider(widget.chatId));
    final stored = messageState.value ?? const <LocalMessage>[];
    final blockState = ref.watch(blockedUidsProvider);
    if (blockState.isLoading || blockState.hasError || !blockState.hasValue) {
      return Scaffold(
        appBar: UiAppBar(context: context, title: const Text('Conversation')),
        body: blockState.isLoading
            ? const Center(child: CircularProgressIndicator())
            : UiEmptyState(
                title: 'Could not load privacy settings',
                message: 'Your conversation stays hidden until these settings are available.',
                action: TextButton(
                  onPressed: () => ref.invalidate(blockedUidsProvider),
                  child: const Text('Try again'),
                ),
              ),
      );
    }
    final pending = ref.watch(pendingLocalSendsProvider);
    for (final send in pending.values) {
      if (send.chatId != widget.chatId) continue;
      final confirmed = stored.any(
        (m) =>
            m.id == send.messageId &&
            m.outgoing &&
            m.status == MessageStatus.ok,
      );
      if (confirmed) {
        _sendController.dropMemoryPending(send.messageId);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref
                .read(pendingLocalSendsProvider.notifier)
                .remove(widget.chatId, send.messageId);
          }
        });
      } else {
        _sendController.rememberMemoryPending(
          send.messageId,
          () => MemoryPending(send),
        );
      }
    }
    final allMessages =
        [
          ...stored,
          for (final m in _sendController.memoryPending.values)
            if (!stored.any((x) => x.id == m.messageId))
              m.asLocalMessage(session),
        ]..sort((a, b) {
          final byTime = a.sentAt.compareTo(b.sentAt);
          return byTime != 0 ? byTime : a.id.compareTo(b.id);
        });
    final target = !_showAll && widget.initialMessageId != null
        ? allMessages.indexWhere((m) => m.id == widget.initialMessageId)
        : -1;
    final msgs = target < 0
        ? allMessages
        : allMessages.take(target + 1).toList();
    final activity = ref.watch(chatActivityProvider);
    final otherUnread = activity.otherUnread(widget.chatId);
    final muted = activity.muted.contains(widget.chatId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _markSeen();
    });
    final visibleIds = msgs.map((m) => m.id).toSet();
    _timeline.pruneAnchors(visibleIds);
    final summary = ref.watch(chatSummaryProvider(widget.chatId));
    final me = session?.uid ?? '';
    final incomingRequest = summary?.isIncomingRequest(me) ?? false;
    final outgoingPending =
        summary != null && !summary.accepted && summary.initiator == me;
    final waiting =
        outgoingPending && summary.requestCount >= ChatService.requestLimit;
    final blocked =
        peerUid != null &&
        (ref.watch(blockedUidsProvider).value?.contains(peerUid) ?? false);
    final identityHeld =
        peerUid != null &&
        ref.watch(identityAlertsProvider).value?.containsKey(peerUid) == true;
    ref.listen(messagesProvider(widget.chatId), (previous, next) {
      if (!_timeline.controller.hasClients || next.hasError) return;
      if (_timeline.controller.offset > 96) {
        final anchor = _timeline.readingAnchor();
        if (anchor != null) _timeline.keepReadingAnchor(anchor);
        return;
      }
      final before = previous?.value;
      final after = next.value;
      if (after == null ||
          after.isEmpty ||
          (before != null &&
              before.isNotEmpty &&
              before.last.id == after.last.id)) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _timeline.jumpToLatestIfNear();
      });
    });
    final verified =
        peerUid != null &&
        ref.watch(peerVerifiedProvider(peerUid)).value == true;

    return Scaffold(
      appBar: UiAppBar(
        context: context,
        toolbarHeight: 64,
        leading: IconButton(
          key: const Key('chatBack'),
          tooltip: otherUnread == 0
              ? 'Back to chats'
              : 'Back to chats, $otherUnread unread messages in other chats',
          onPressed: () => Navigator.maybePop(context),
          icon: Badge(
            isLabelVisible: otherUnread > 0,
            label: Text(unreadLabel(otherUnread)),
            child: const BackButtonIcon(),
          ),
        ),
        title: Row(
          children: [
            PersonAvatar(name: name, size: 36),
            SizedBox(width: 10),
            Expanded(
              child: InkWell(
                key: const Key('chatDetails'),
                onTap: peerUid == null || session == null
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ChatDetailsScreen(
                            peerUid: peerUid,
                            chatId: widget.chatId,
                            name: name,
                            onBlock: () => _blockPeer(session, peerUid, name),
                            onUnblock: () => session.safety.unblock(peerUid),
                          ),
                        ),
                      ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(name, overflow: TextOverflow.ellipsis),
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (peerUid != null)
            IconButton(
              key: Key('verify'),
              tooltip: 'Verify security code',
              icon: Icon(
                verified ? Icons.verified_user : Icons.shield_outlined,
                color: verified ? Theme.of(context).colorScheme.primary : null,
              ),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      VerifyScreen(peerUid: peerUid, peerName: name),
                ),
              ),
            ),
          if (peerUid != null && session != null)
            PopupMenuButton<String>(
              key: Key('chatMenu'),
              onSelected: (v) async {
                if (v == 'mute') {
                  await _mute(!muted);
                } else if (v == 'block') {
                  await _contactController.contactAction(
                    () => _blockPeer(session, peerUid, name),
                  );
                } else if (v == 'unblock') {
                  await _contactController.contactAction(
                    () => session.safety.unblock(peerUid),
                  );
                } else if (v == 'report') {
                  await _contactController.contactAction(() async {
                    await showReportDialog(
                      context,
                      ref,
                      peerUid: peerUid,
                      name: name,
                      chatId: widget.chatId,
                    );
                  });
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  key: const Key('menuMute'),
                  value: 'mute',
                  child: Text(muted ? 'Unmute chat' : 'Mute chat'),
                ),
                PopupMenuItem(
                  key: Key('menuBlock'),
                  value: blocked ? 'unblock' : 'block',
                  child: Text(blocked ? 'Unblock' : 'Block'),
                ),
                PopupMenuItem(
                  key: Key('menuReport'),
                  value: 'report',
                  child: Text('Report'),
                ),
              ],
            ),
        ],
      ),
      body: UiBodyViewport(
        anchorBottom: true,
        child: Column(
          children: [
            if (!_showAll && widget.initialMessageId != null)
              UiNotice(
                key: const Key('searchLocation'),
                text: target < 0
                    ? 'This search result is no longer on this device.'
                    : 'Search result — showing messages up to this point.',
                actions: [
                  TextButton(
                    onPressed: () {
                      setState(() => _showAll = true);
                      _latest();
                    },
                    child: const Text('Show latest messages'),
                  ),
                ],
              ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: math.max(
                  48,
                  (MediaQuery.sizeOf(context).height -
                          MediaQuery.viewInsetsOf(context).bottom) *
                      (MediaQuery.sizeOf(context).height > 650 ? .45 : .33),
                ),
              ),
              child: SingleChildScrollView(
                key: const Key('chatSafetyNotices'),
                child: Column(
                  children: [
                    if (peerUid != null && session != null)
                      IdentityAlertBanner(
                        peerUid: peerUid,
                        name: name,
                        busy: _contactController.reviewing,
                        onReview: (pub) =>
                            _contactController.reviewIdentity(peerUid, pub),
                      ),
                    if (peerUid != null)
                      NewDeviceBanner(peerUid: peerUid, name: name),
                    if (incomingRequest && session != null && peerUid != null)
                      RequestBanner(
                        name: name,
                        busy: _contactController.busy,
                        onAccept: () => _contactController.contactAction(
                          () => session.chat.acceptRequest(widget.chatId),
                        ),
                        onBlock: () => _contactController.contactAction(
                          () => _blockPeer(session, peerUid, name),
                        ),
                        onReport: () =>
                            _contactController.contactAction(() async {
                              await showReportDialog(
                                context,
                                ref,
                                peerUid: peerUid,
                                name: name,
                                chatId: widget.chatId,
                              );
                            }),
                      ),
                    if (_contactController.error != null)
                      UiNotice(warning: true, text: _contactController.error!),
                    if (_sendController.sendError != null)
                      UiNotice(
                        key: const Key('sendFailure'),
                        warning: true,
                        brandText: true,
                        text: _sendController.sendError!,
                        actions: [
                          TextButton(
                            onPressed: () => _sendController.dismissError(),
                            child: const Text('Dismiss'),
                          ),
                        ],
                      ),
                    if (outgoingPending && !waiting)
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        child: Text(
                          'Message request sent. @$name sees it once they accept '
                          '(${ChatService.requestLimit - summary.requestCount} left).',
                          key: Key('requestSentNote'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Stack(
                key: _timeline.viewportKey,
                fit: StackFit.expand,
                children: [
                  blocked
                      ? const UiEmptyState(
                          title: 'Conversation hidden',
                          message: 'Unblock this contact in Settings to see your history again.',
                        )
                      : messageState.hasError
                      ? UiEmptyState(
                          title: 'Could not load history',
                          message:
                              'Try again to read the history on this device.',
                          action: TextButton(
                            onPressed: () =>
                                ref.invalidate(messagesProvider(widget.chatId)),
                            child: const Text('Try again'),
                          ),
                        )
                      : messageState.isLoading && msgs.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : msgs.isEmpty
                      ? UiEmptyState(
                          icon: Icons.lock_outline_rounded,
                          title: incomingRequest
                              ? 'A new message request'
                              : 'A private conversation',
                          message: incomingRequest
                              ? 'Messages stay hidden until you accept.'
                              : 'Messages are end-to-end encrypted. Say hello when you’re ready.',
                        )
                      : ListView.builder(
                          key: const Key('messageTimeline'),
                          controller: _timeline.controller,
                          reverse: true,
                          padding: EdgeInsets.all(12),
                          itemCount: msgs.length,
                          itemBuilder: (_, i) {
                            final index = msgs.length - 1 - i;
                            final message = msgs[index];
                            final showDate =
                                index == 0 ||
                                !sameLocalDay(
                                  msgs[index - 1].sentAt,
                                  message.sentAt,
                                );
                            return Column(
                              key: ValueKey(message.id),
                              children: [
                                if (showDate)
                                  DaySeparator(date: message.sentAt),
                                MessageBubble(
                                  key: _timeline.anchorFor(message.id),
                                  message: message,
                                  senderName: name,
                                  actions: _actionsFor(
                                    message,
                                    name: name,
                                    peerUid: peerUid,
                                    blocked: blocked,
                                    incomingRequest: incomingRequest,
                                    identityHeld: identityHeld,
                                  ),
                                ),
                                if (message.outgoing &&
                                    (message.status ==
                                            MessageStatus.unconfirmed ||
                                        _sendController
                                                .memoryPending[message.id]
                                                ?.outcome ==
                                            SendOutcome
                                                .publishedLocalSaveFailed))
                                  UnconfirmedNote(
                                    messageId: message.id,
                                    savedLocallyFailed:
                                        _sendController
                                            .memoryPending[message.id]
                                            ?.outcome ==
                                        SendOutcome.publishedLocalSaveFailed,
                                    action: _sendController
                                        .messageActions[message.id],
                                    note: _sendController.checkNote[message.id],
                                    onCheck: () =>
                                        _sendController.checkStatus(message.id),
                                    onSendAgain: () => _sendController
                                        .sendAgain(message.id, message.body),
                                    onSave: () {
                                      final mem = _sendController
                                          .memoryPending[message.id];
                                      if (mem != null) {
                                        _sendController.saveOnDevice(mem);
                                      }
                                    },
                                  ),
                              ],
                            );
                          },
                        ),
                  if (_timeline.awayFromLatest && msgs.isNotEmpty)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 8,
                      child: Align(
                        alignment: Alignment.bottomRight,
                        child: FilledButton(
                          key: const Key('latestMessages'),
                          onPressed: _latest,
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.arrow_downward, size: 18),
                              SizedBox(width: 8),
                              Flexible(child: Text('Latest messages')),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (blocked)
              ComposerNote(
                key: Key('blockedNote'),
                text: 'You blocked @$name.',
                action: TextButton(
                  onPressed: session == null || _contactController.busy
                      ? null
                      : () => _contactController.contactAction(
                          () => session.safety.unblock(peerUid),
                        ),
                  child: Text('Unblock'),
                ),
              )
            else if (incomingRequest)
              ComposerNote(
                key: Key('acceptToReplyNote'),
                text: 'Accept this request to reply.',
              )
            else if (waiting)
              ComposerNote(
                key: Key('waitingNote'),
                text: 'Waiting for @$name to accept your request.',
              )
            else if (identityHeld)
              ComposerNote(
                key: Key('identityHeldNote'),
                text: 'Review this contact’s security code before sending.',
              )
            else
              SafeArea(
                top: false,
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(
                      LogicalKeyboardKey.enter,
                      control: true,
                    ): _sendController.send,
                    const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                        _sendController.send,
                  },
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    decoration: BoxDecoration(
                      color: FireplaceUiTokens.of(context).panel,
                      border: Border(
                        top: BorderSide(
                          color: FireplaceUiTokens.of(context).separator,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight:
                                  ((MediaQuery.sizeOf(context).height -
                                              MediaQuery.viewInsetsOf(context)
                                                  .bottom) *
                                          .35)
                                      .clamp(120, 280),
                            ),
                            child: TextField(
                              key: Key('composer'),
                              controller: _text,
                              inputFormatters: [MessageInputFormatter()],
                              minLines: 1,
                              maxLines:
                                  MediaQuery.sizeOf(context).height -
                                          MediaQuery.viewInsetsOf(context)
                                              .bottom <
                                      500
                                  ? 3
                                  : 6,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: InputDecoration(
                                counter:
                                    messageCharacters(_text.text) >=
                                        (maxMessageCharacters * .9).floor()
                                    ? Text(
                                        '${messageCharacters(_text.text)} / 16,384',
                                        key: const Key('messageCounter'),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      )
                                    : null,
                                hintText: 'Message',
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                              ),
                              textInputAction: TextInputAction.newline,
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        IconButton.filled(
                          key: Key('send'),
                          style: IconButton.styleFrom(
                            minimumSize: const Size(48, 48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .primary,
                            foregroundColor: Theme.of(context)
                                .colorScheme
                                .onPrimary,
                          ),
                          onPressed:
                              _sendController.sending ||
                                  _text.text.trim().isEmpty ||
                                  session == null
                              ? null
                              : _sendController.send,
                          tooltip: _sendController.sending
                              ? 'Sending message'
                              : 'Send message',
                          icon: _sendController.sending
                              ? SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onPrimary,
                                  ),
                                )
                              : Icon(Icons.arrow_upward_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
