import 'package:fireplace/src/view/chat/quote_navigation.dart';
import 'package:fireplace/src/view/chat/composer/message_composer_context.dart';
import 'package:fireplace/src/model/chat/message_compose_target.dart';
import 'package:fireplace/src/view/chat/chat_unavailable.dart';
import 'package:fireplace/src/view/chat/message_selection_surface.dart';
import 'package:fireplace/src/model/chat/message_selection.dart';
import 'package:fireplace/src/model/chat/pinned_messages.dart';
import 'package:fireplace/src/view/chat/chat_timeline.dart';
import 'package:fireplace/src/view/chat/pinned_bar.dart';
import 'package:fireplace/src/view/chat/chat_app_bar_parts.dart';
import 'package:fireplace/src/view/chat/chat_safety_notices.dart';
import 'package:fireplace/src/view/chat/review_chat_identity.dart';
import 'package:fireplace/src/view/chat/chat_composer.dart';
import 'package:fireplace/src/view/chat/message_menu.dart';
import 'package:fireplace/src/view/chat/route_visibility.dart';
import 'package:fireplace/src/view/chat/timeline_scroll.dart';
import 'package:fireplace/src/model/chat/contact_controller.dart';
import 'package:fireplace/src/model/chat/send_controller.dart';
import 'package:fireplace/src/model/chat/outgoing_sends.dart';
import 'package:fireplace/src/view/chat/outgoing_messages.dart';
import 'package:fireplace/src/model/chat/memory_pending.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/model/chat/chat_service.dart';
import 'package:fireplace/src/view/safety/confirm_block.dart';
import 'package:fireplace/src/view/safety/report_spam.dart';
import 'package:fireplace/src/widgets/app_bar.dart';
import 'package:fireplace/src/view/chat/confirm_another_copy.dart';
import 'package:fireplace/src/widgets/page.dart';
import 'package:fireplace/src/view/safety/verify_screen.dart';
import 'package:fireplace/src/view/chat/chat_details_screen.dart';
import 'package:fireplace/src/model/chat/chat_visibility.dart';
import 'package:fireplace/src/model/notifications/chat_activity.dart';
import 'package:fireplace/src/model/chat/pending_sends.dart';
import 'package:fireplace/src/model/chat/chat_drafts.dart';
import 'package:fireplace/src/view/chat/composer/chat_draft_controller.dart';

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
  String? get _location => widget.initialMessageId;
  late final ChatDraftController _text;
  late final SendController _sendController;
  late final TimelineScroll _timeline;

  late final ContactController _contactController;
  @override
  void initState() {
    super.initState();
    _text = ChatDraftController(
      drafts: ref.read(chatDraftsProvider.notifier),
      chatId: widget.chatId,
      ownerUid: ref.read(appSessionProvider).value?.uid,
    );
    _contactController =
        ContactController(
          reviewOnce: (peerUid, pub) async {
            final session = ref.read(appSessionProvider).value;
            if (session != null) {
              await reviewChatIdentity(
                context,
                session,
                peerUid,
                pub,
                isMounted: () => mounted,
                notice: _snack,
              );
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
          enqueue: (body, reply) => ref
              .read(outgoingSendsProvider.notifier)
              .enqueue(widget.chatId, body, replyTarget: reply),
          replyTarget: () =>
              ref.read(messageComposeProvider(widget.chatId))?.replyId,
          clearDraft: _text.clear,
          clearReply: () => ref
              .read(messageComposeProvider(widget.chatId).notifier)
              .clearReply(),
          notice: _snack,
          showNewest: () => _timeline.showNewestAfterOwnSend(_latest),
          identityAlerts: () => ref.read(identityAlertsProvider).value ?? {},
          confirmSendAnotherCopy: () => confirmAnotherMessageCopy(context),
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
  @visibleForTesting
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
    final index = !_showAll && _location != null
        ? messages.indexWhere((m) => m.id == _location)
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
    if (mounted) setState(() {});
  }

  void _latest() {
    if (!_showAll && _location != null) {
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

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
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

  /// The profile already confirmed. Leave the chat once the block is stored.
  Future<void> _blockFromProfile(AppSession session, String peerUid) async {
    await session.safety.block(peerUid);
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _reportSpam(
    AppSession session,
    String peerUid,
    ReportSpamChoice choice,
  ) async {
    await session.safety.reportSpam(peerUid);
    if (!mounted) return;
    if (choice == ReportSpamChoice.reportAndBlock) {
      await session.safety.block(peerUid);
      if (!mounted) return;
      _snack('Reported as spam and blocked.');
      Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    }
    _snack('Reported as spam.');
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
      return ChatUnavailableScreen();
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
      return ChatPrivacyErrorScreen(
        loading: blockState.isLoading,
        onRetry: () => ref.invalidate(blockedUidsProvider),
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
    final history = [
      for (final message in allMessages)
        if (!message.remotelyDeleted) message,
    ];
    final target = !_showAll && _location != null
        ? history.indexWhere((m) => m.id == _location)
        : -1;
    final outgoing = {
      for (final send in ref.watch(outgoingSendsProvider))
        if (send.chatId == widget.chatId) send.id: send,
    };
    final msgs = target < 0
        ? [...history, ...outgoingBubbles(outgoing.values, stored, session)]
        : history.take(target + 1).toList();
    reviewIdentityOnFailedSend(
      ref,
      widget.chatId,
      _contactController.reviewIdentity,
    );
    final activity = ref.watch(chatActivityProvider);
    final otherUnread = activity.otherUnread(widget.chatId);
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
      if (_timeline.controller.offset > 96 && !_timeline.returningToLatest) {
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

    final selecting = ref.watch(
      messageSelectionProvider(widget.chatId)
          .select((selection) => selection.active),
    );
    final pinnedIds =
        ref.watch(pinnedMessagesProvider)[widget.chatId] ?? const <String>[];
    final pinned = [
      for (final id in pinnedIds)
        ?history.where((message) => message.id == id).firstOrNull,
    ];
    ChatTitle chatTitle() => ChatTitle(
      name: name,
      peerUid: peerUid,
      hasSession: session != null,
      onOpenDetails: (partContext) => Navigator.of(partContext).push(
        MaterialPageRoute(
          builder: (_) => ChatDetailsScreen(
            peerUid: peerUid!,
            chatId: widget.chatId,
            name: name,
            onMute: _mute,
            onBlock: () => _blockFromProfile(session!, peerUid),
            onUnblock: () => session!.safety.unblock(peerUid),
            onReportSpam: (choice) => _reportSpam(session!, peerUid, choice),
          ),
        ),
      ),
    );
    return MessageSelectionSurface(
      chatId: widget.chatId,
      selectionTitle: chatTitle(),
      onDeleted: (ids) {
        for (final id in ids) {
          _sendController.forgetPending(id);
        }
        if (mounted) setState(() {});
      },
      appBar: UiAppBar(
        context: context,
        toolbarHeight: 64,
        leading: ChatBackButton(otherUnread: otherUnread),
        title: chatTitle(),
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
        ],
      ),
      body: UiBodyViewport(
        anchorBottom: true,
        child: Column(
          children: [
            if (!_showAll && _location != null)
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
            ),
            if (pinned.isNotEmpty)
              PinnedBar(
                messages: pinned,
                onOpen: (id) {
                  final anchor = _timeline.anchorFor(id).currentContext;
                  if (anchor != null) {
                    Scrollable.ensureVisible(
                      anchor,
                      alignment: 0.3,
                      duration: const Duration(milliseconds: 200),
                    );
                  }
                },
              ),
            Expanded(
              child: ChatTimeline(
                chatId: widget.chatId,
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
                outgoing: outgoing,
                onFailedSend: (send) => chooseForFailedSend(
                  context,
                  ref,
                  send,
                  onSendAgain: () => _timeline.showNewestAfterOwnSend(_latest),
                ),
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
                onQuote: (id) => locateQuotedMessage(
                  context,
                  _timeline,
                  history,
                  id,
                  revealAll: () => setState(() => _showAll = true),
                  notice: _snack,
                ),
                onLatest: _latest,
              ),
            ),
            if (!selecting)
              MessageComposerContext(
                chatId: widget.chatId,
                name: name,
                builder: (context, composer) => ChatComposer(
                  focusNode: composer.focus,
                  contextBar: composer.bar,
                  submit: composer.submit,
                  editing: composer.editText != null,
                  editingBusy: composer.busy,
                  canSubmit: composer.canSubmit,
                  onInteraction: () => ref
                      .read(messageSelectionProvider(widget.chatId).notifier)
                      .clear(),
                  keyboardInset: keyboardInset,
                  text: composer.editText ?? _text,
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
              ),
          ],
        ),
      ),
    );
  }
}
