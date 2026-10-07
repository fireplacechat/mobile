import 'package:fireplace/src/view/chat/chat_timeline.dart';
import 'package:fireplace/src/view/chat/chat_app_bar_parts.dart';
import 'package:fireplace/src/view/chat/chat_safety_notices.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/view/chat/chat_composer.dart';
import 'package:fireplace/src/view/chat/message_menu.dart';
import 'package:fireplace/src/view/chat/route_visibility.dart';
import 'package:fireplace/src/view/chat/timeline_scroll.dart';
import 'package:fireplace/src/model/chat/contact_controller.dart';
import 'package:fireplace/src/model/chat/send_controller.dart';
import 'package:fireplace/src/model/chat/memory_pending.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/crypto/fingerprint.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/services/chat_service.dart';
import 'package:fireplace/src/ui/safety_ui.dart';
import 'package:fireplace/src/ui/presentation.dart';
import 'package:fireplace/src/view/safety/verify_screen.dart';
import 'package:fireplace/src/view/chat/chat_details_screen.dart';
import 'package:fireplace/src/ui/chat_activity.dart';
import 'package:fireplace/src/model/chat/pending_sends.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.chatId, this.initialMessageId});
  final String chatId;
  final String? initialMessageId;
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  String? _ownerUid;
  late final RouteVisibility _routeVisibility;
  bool _showAll = false;
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
    _routeVisibility = RouteVisibility(
      chatId: () => widget.chatId,
      notifier: ref.read(visibleChatProvider.notifier),
      currentlyVisible: () => ref.read(visibleChatProvider),
      isMounted: () => mounted,
      onVisible: _markSeen,
    )..start();
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
    if (route is ModalRoute<void>) {
      _routeVisibility.subscribe(route);
    }
  }

  // Kept for the existing lifecycle characterization tests.
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _routeVisibility.didChangeAppLifecycleState(state);

  void _markSeen() {
    if (!_routeVisibility.foreground ||
        !_routeVisibility.isCurrentRoute ||
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
    _routeVisibility.dispose();
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
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final verified =
        peerUid != null &&
        ref.watch(peerVerifiedProvider(peerUid)).value == true;

    return Scaffold(
      appBar: UiAppBar(
        context: context,
        toolbarHeight: 64,
        leading: ChatBackButton(otherUnread: otherUnread),
        title: ChatTitle(
          name: name,
          peerUid: peerUid,
          hasSession: session != null,
          onOpenDetails: (partContext) => Navigator.of(partContext).push(
            MaterialPageRoute(
              builder: (_) => ChatDetailsScreen(
                peerUid: peerUid!,
                chatId: widget.chatId,
                name: name,
                onBlock: () => _blockPeer(session!, peerUid, name),
                onUnblock: () => session!.safety.unblock(peerUid),
              ),
            ),
          ),
        ),
        actions: [
          if (peerUid != null)
            ChatVerifyButton(
              verified: verified,
              onPressed: (partContext) => Navigator.of(partContext).push(
                MaterialPageRoute(
                  builder: (_) =>
                      VerifyScreen(peerUid: peerUid, peerName: name),
                ),
              ),
            ),
          if (peerUid != null && session != null)
            ChatOverflowMenu(
              muted: muted,
              blocked: blocked,
              onMute: () => _mute(!muted),
              onBlock: () => _contactController.contactAction(
                () => _blockPeer(session, peerUid, name),
              ),
              onUnblock: () => _contactController.contactAction(
                () => session.safety.unblock(peerUid),
              ),
              onReport: () => _contactController.contactAction(() async {
                await showReportDialog(
                  context,
                  ref,
                  peerUid: peerUid,
                  name: name,
                  chatId: widget.chatId,
                );
              }),
            ),
        ],
      ),
      body: UiBodyViewport(
        anchorBottom: true,
        child: Column(
          children: [
            if (!_showAll && widget.initialMessageId != null)
              SearchLocationNotice(
                target: target,
                onShowLatest: () {
                  setState(() => _showAll = true);
                  _latest();
                },
              ),
            ChatSafetyNotices(
              peerUid: peerUid,
              name: name,
              hasSession: session != null,
              incomingRequest: incomingRequest,
              outgoingPending: outgoingPending,
              waiting: waiting,
              requestsLeft:
                  ChatService.requestLimit - (summary?.requestCount ?? 0),
              contact: _contactController,
              send: _sendController,
              keyboardInset: keyboardInset,
              onReviewIdentity: (pub) =>
                  _contactController.reviewIdentity(peerUid!, pub),
              onAccept: () => _contactController.contactAction(
                () => session!.chat.acceptRequest(widget.chatId),
              ),
              onBlock: () => _contactController.contactAction(
                () => _blockPeer(session!, peerUid!, name),
              ),
              onReport: () => _contactController.contactAction(() async {
                await showReportDialog(
                  context,
                  ref,
                  peerUid: peerUid!,
                  name: name,
                  chatId: widget.chatId,
                );
              }),
            ),
            Expanded(
              child: ChatTimeline(
                blocked: blocked,
                historyFailed: messageState.hasError,
                loading: messageState.isLoading,
                msgs: msgs,
                incomingRequest: incomingRequest,
                name: name,
                awayFromLatest: _timeline.awayFromLatest,
                viewportKey: _timeline.viewportKey,
                scrollController: _timeline.controller,
                anchorFor: _timeline.anchorFor,
                send: _sendController,
                actionsFor: (message) => messageMenuActions(
                  message,
                  ref: ref,
                  context: context,
                  isMounted: () => mounted,
                  notice: _snack,
                  chatId: () => widget.chatId,
                  contactAction: _contactController.contactAction,
                  name: name,
                  peerUid: peerUid,
                  blocked: blocked,
                  incomingRequest: incomingRequest,
                  identityHeld: identityHeld,
                ),
                onRetryHistory: () =>
                    ref.invalidate(messagesProvider(widget.chatId)),
                onLatest: _latest,
              ),
            ),
            ChatComposer(
              keyboardInset: keyboardInset,
              text: _text,
              name: name,
              blocked: blocked,
              incomingRequest: incomingRequest,
              waiting: waiting,
              identityHeld: identityHeld,
              hasSession: session != null,
              contactBusy: _contactController.busy,
              send: _sendController,
              onUnblock: () => _contactController.contactAction(
                () => session!.safety.unblock(peerUid!),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
