import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/crypto/fingerprint.dart';
import 'package:fireplace/src/model/keys/key_service.dart';
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

enum _MessageAction { checking, resending, saving }

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
  final _scroll = ScrollController();
  final _timelineViewport = GlobalKey();
  final _messageAnchors = <String, GlobalKey>{};
  bool _sending = false;
  bool _awayFromLatest = false;
  int _draftRevision = 0;
  String _lastDraftText = '';

  /// Messages whose outcome could not be saved in the on-device history (the storage itself
  /// failed), so the warning lives in memory only. Keyed by the server message id.
  final Map<String, _MemoryPending> _memoryPending = {};
  final _messageActions = <String, _MessageAction>{};
  String? _sendError;
  bool _contactBusy = false, _reviewing = false;
  String? _contactError;
  final Map<String, String> _checkNote = {};
  @override
  void initState() {
    super.initState();
    _visibilityNotifier = ref.read(visibleChatProvider.notifier);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _text.addListener(_onDraftChanged);
    _scroll.addListener(_onTimelineScroll);
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
            () => _contactAction(() async {
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

  void _onTimelineScroll() {
    final away = _scroll.hasClients && _scroll.offset > 96;
    if (away != _awayFromLatest && mounted) {
      setState(() => _awayFromLatest = away);
    }
  }

  (GlobalKey, double)? _readingAnchor() {
    final viewport = _timelineViewport.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) return null;
    final top = viewport.localToGlobal(Offset.zero).dy;
    final bottom = top + viewport.size.height;
    (GlobalKey, double)? anchor;
    for (final key in _messageAnchors.values) {
      final box = key.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize || !box.attached) continue;
      final y = box.localToGlobal(Offset.zero).dy;
      if (y < bottom &&
          y + box.size.height > top &&
          (anchor == null || (y - top).abs() < (anchor.$2 - top).abs())) {
        anchor = (key, y);
      }
    }
    return anchor;
  }

  void _keepReadingAnchor((GlobalKey, double) anchor) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients || _scroll.offset <= 96) return;
      final box = anchor.$1.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize || !box.attached) return;
      // The reversed timeline grows upwards. Restore the visible message's
      // position rather than the numeric offset from its changing bottom.
      final shift = box.localToGlobal(Offset.zero).dy - anchor.$2;
      final target = (_scroll.offset - shift).clamp(
        0.0,
        _scroll.position.maxScrollExtent,
      );
      if (shift.abs() > .5) _scroll.jumpTo(target);
    });
  }

  /// The user just sent something: show it, even if they had scrolled up to read older messages
  /// (a message that ARRIVES while reading still never moves the view).
  void _showNewestAfterOwnSend() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _latest();
    });
  }

  void _latest() {
    if (!_showAll && widget.initialMessageId != null) {
      setState(() => _showAll = true);
    }
    if (!_scroll.hasClients) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(0);
    } else {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
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
    _scroll.removeListener(_onTimelineScroll);
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (messageTooLong(_text.text)) {
      setState(() => _sendError = messageLimitError);
      return;
    }
    final body = _text.text.trim();
    final session = ref.read(appSessionProvider).value;
    if (body.isEmpty || session == null || _sending) return;
    final peerUid = session.chat.peerOf(widget.chatId);
    if (ref.read(identityAlertsProvider).value?.containsKey(peerUid) == true) {
      _snack('Review the security code change before sending.');
      return;
    }
    final draftRevision = _draftRevision;
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      await session.chat.sendText(widget.chatId, body);
      if (!mounted) return;
      if (_draftRevision == draftRevision) _text.clear();
      _showNewestAfterOwnSend();
    } on SendNotConfirmedException catch (e) {
      // The message may already have been delivered, so this is NOT a plain failure: the attempted
      // draft moves into a pending bubble (warning below it) instead of staying poised to resend.
      if (!mounted) return;
      if (!e.persisted) {
        ref
            .read(pendingLocalSendsProvider.notifier)
            .add(e, ownerUid: session.uid);
        setState(() => _memoryPending[e.messageId] = _MemoryPending(e));
      }
      // Edits made while the send was in flight survive: only an untouched draft is cleared.
      if (_draftRevision == draftRevision) _text.clear();
      _showNewestAfterOwnSend();
    } on IdentityChangedException catch (e) {
      if (mounted) await _reviewIdentity(session, e.peerUid, e.newIdentityPub);
    } on ChatException catch (e) {
      if (mounted) setState(() => _sendError = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _sendError = 'We could not confirm this send. It may have reached them. Check your history before sending again.',
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _forgetPending(String id) {
    _memoryPending.remove(id);
    ref.read(pendingLocalSendsProvider.notifier).remove(widget.chatId, id);
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  /// Asks the server whether the message exists. Never publishes anything.
  Future<void> _checkStatus(String messageId) async {
    final session = ref.read(appSessionProvider).value;
    if (session == null || _messageActions.containsKey(messageId)) return;
    setState(() {
      _messageActions[messageId] = _MessageAction.checking;
      _checkNote.remove(messageId);
    });
    try {
      final outcome = await session.chat.checkSendStatus(
        widget.chatId,
        messageId,
      );
      if (!mounted) return;
      if (outcome == SendOutcome.confirmed) {
        final mem = _memoryPending[messageId];
        if (mem != null) {
          mem.outcome = SendOutcome.publishedLocalSaveFailed;
          ref
              .read(pendingLocalSendsProvider.notifier)
              .confirmed(widget.chatId, messageId, ownerUid: session.uid);
          try {
            await session.chat.saveSentLocally(
              chatId: widget.chatId,
              messageId: messageId,
              body: mem.body,
              sentAt: mem.sentAt,
            );
            _forgetPending(messageId);
          } catch (_) {
            // Still held in memory; the message is confirmed on the server.
          }
        }
        _snack('Message confirmed: it reached the server.');
      } else {
        setState(
          () => _checkNote[messageId] =
              'Still not sure. It may or may not have been delivered.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _checkNote[messageId] =
              'Could not check yet. Nothing was sent again. Try later.',
        );
      }
    } finally {
      if (mounted) setState(() => _messageActions.remove(messageId));
    }
  }

  /// The explicit "send another copy" decision.
  Future<void> _sendAgain(String messageId, String body) async {
    final session = ref.read(appSessionProvider).value;
    if (session == null || _messageActions.containsKey(messageId)) return;
    setState(() => _messageActions[messageId] = _MessageAction.resending);
    try {
      final go = await showDialog<bool>(
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
      if (go != true || !mounted) return;
      await session.chat.resendUnconfirmed(
        chatId: widget.chatId,
        messageId: messageId,
        body: body,
      );
      if (mounted) setState(() => _forgetPending(messageId));
    } on SendNotConfirmedException catch (e) {
      if (mounted && !e.persisted) {
        ref
            .read(pendingLocalSendsProvider.notifier)
            .add(e, ownerUid: session.uid);
        setState(() => _memoryPending[e.messageId] = _MemoryPending(e));
      }
    } on ChatException catch (e) {
      if (mounted) setState(() => _checkNote[messageId] = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _checkNote[messageId] = 'The new copy is not confirmed. It may have reached them. Do not send another copy without checking.',
        );
      }
    } finally {
      if (mounted) setState(() => _messageActions.remove(messageId));
    }
  }

  /// Repairs local history for a message known to be on the server. No publish.
  Future<void> _saveOnDevice(_MemoryPending mem) async {
    final session = ref.read(appSessionProvider).value;
    if (session == null || _messageActions.containsKey(mem.messageId)) return;
    setState(() => _messageActions[mem.messageId] = _MessageAction.saving);
    try {
      await session.chat.saveSentLocally(
        chatId: widget.chatId,
        messageId: mem.messageId,
        body: mem.body,
        sentAt: mem.sentAt,
      );
      if (mounted) setState(() => _forgetPending(mem.messageId));
    } catch (_) {
      if (mounted) {
        setState(
          () => _checkNote[mem.messageId] = 'Could not save on this device yet. Your message was sent: do not send it again.',
        );
      }
    } finally {
      if (mounted) setState(() => _messageActions.remove(mem.messageId));
    }
  }

  /// Lets the user compare and explicitly decide about a changed contact key.
  /// Nothing is trusted automatically.
  Future<void> _contactAction(Future<void> Function() action) async {
    if (_contactBusy) return;
    setState(() {
      _contactBusy = true;
      _contactError = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(
          () => _contactError = 'Could not update this contact. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _contactBusy = false);
    }
  }

  Future<void> _reviewIdentity(
    AppSession session,
    String peerUid,
    List<int> pub,
  ) async {
    if (_reviewing) return;
    setState(() => _reviewing = true);
    try {
      await _reviewIdentityOnce(session, peerUid, pub);
    } catch (_) {
      if (mounted) {
        setState(
          () => _contactError = 'Could not finish the security review. Check this contact’s security code before continuing. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _reviewing = false);
    }
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
      if (session?.uid != _ownerUid) _memoryPending.clear();
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
        _memoryPending.remove(send.messageId);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref
                .read(pendingLocalSendsProvider.notifier)
                .remove(widget.chatId, send.messageId);
          }
        });
      } else {
        _memoryPending.putIfAbsent(send.messageId, () => _MemoryPending(send));
      }
    }
    final allMessages =
        [
          ...stored,
          for (final m in _memoryPending.values)
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
    _messageAnchors.removeWhere((id, _) => !visibleIds.contains(id));
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
      if (!_scroll.hasClients || next.hasError) return;
      if (_scroll.offset > 96) {
        final anchor = _readingAnchor();
        if (anchor != null) _keepReadingAnchor(anchor);
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
        if (mounted && _scroll.hasClients && _scroll.offset <= 96) {
          _scroll.jumpTo(0);
        }
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
                  await _contactAction(
                    () => _blockPeer(session, peerUid, name),
                  );
                } else if (v == 'unblock') {
                  await _contactAction(() => session.safety.unblock(peerUid));
                } else if (v == 'report') {
                  await _contactAction(() async {
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
                      _IdentityAlertBanner(
                        peerUid: peerUid,
                        name: name,
                        busy: _reviewing,
                        onReview: (pub) =>
                            _reviewIdentity(session, peerUid, pub),
                      ),
                    if (peerUid != null)
                      _NewDeviceBanner(peerUid: peerUid, name: name),
                    if (incomingRequest && session != null && peerUid != null)
                      _RequestBanner(
                        name: name,
                        busy: _contactBusy,
                        onAccept: () => _contactAction(
                          () => session.chat.acceptRequest(widget.chatId),
                        ),
                        onBlock: () => _contactAction(
                          () => _blockPeer(session, peerUid, name),
                        ),
                        onReport: () => _contactAction(() async {
                          await showReportDialog(
                            context,
                            ref,
                            peerUid: peerUid,
                            name: name,
                            chatId: widget.chatId,
                          );
                        }),
                      ),
                    if (_contactError != null)
                      UiNotice(warning: true, text: _contactError!),
                    if (_sendError != null)
                      UiNotice(
                        key: const Key('sendFailure'),
                        warning: true,
                        brandText: true,
                        text: _sendError!,
                        actions: [
                          TextButton(
                            onPressed: () => setState(() => _sendError = null),
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
                key: _timelineViewport,
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
                          controller: _scroll,
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
                                  key: _messageAnchors.putIfAbsent(
                                    message.id,
                                    GlobalKey.new,
                                  ),
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
                                        _memoryPending[message.id]?.outcome ==
                                            SendOutcome
                                                .publishedLocalSaveFailed))
                                  _UnconfirmedNote(
                                    messageId: message.id,
                                    savedLocallyFailed:
                                        _memoryPending[message.id]?.outcome ==
                                        SendOutcome.publishedLocalSaveFailed,
                                    action: _messageActions[message.id],
                                    note: _checkNote[message.id],
                                    onCheck: () => _checkStatus(message.id),
                                    onSendAgain: () =>
                                        _sendAgain(message.id, message.body),
                                    onSave: () {
                                      final mem = _memoryPending[message.id];
                                      if (mem != null) _saveOnDevice(mem);
                                    },
                                  ),
                              ],
                            );
                          },
                        ),
                  if (_awayFromLatest && msgs.isNotEmpty)
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
              _ComposerNote(
                key: Key('blockedNote'),
                text: 'You blocked @$name.',
                action: TextButton(
                  onPressed: session == null || _contactBusy
                      ? null
                      : () => _contactAction(
                          () => session.safety.unblock(peerUid),
                        ),
                  child: Text('Unblock'),
                ),
              )
            else if (incomingRequest)
              _ComposerNote(
                key: Key('acceptToReplyNote'),
                text: 'Accept this request to reply.',
              )
            else if (waiting)
              _ComposerNote(
                key: Key('waitingNote'),
                text: 'Waiting for @$name to accept your request.',
              )
            else if (identityHeld)
              _ComposerNote(
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
                    ): _send,
                    const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                        _send,
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
                              _sending ||
                                  _text.text.trim().isEmpty ||
                                  session == null
                              ? null
                              : _send,
                          tooltip: _sending
                              ? 'Sending message'
                              : 'Send message',
                          icon: _sending
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

class _ComposerNote extends StatelessWidget {
  const _ComposerNote({super.key, required this.text, this.action});
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: math.max(
          72,
          (MediaQuery.sizeOf(context).height -
                  MediaQuery.viewInsetsOf(context).bottom) *
              .3,
        ),
      ),
      child: SingleChildScrollView(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(text),
              if (action != null)
                Align(alignment: Alignment.centerRight, child: action!),
            ],
          ),
        ),
      ),
    ),
  );
}

class _RequestBanner extends StatelessWidget {
  const _RequestBanner({
    required this.name,
    required this.onAccept,
    required this.onBlock,
    required this.onReport,
    this.busy = false,
  });
  final bool busy;
  final String name;
  final VoidCallback onAccept, onBlock, onReport;
  @override
  Widget build(BuildContext context) => UiNotice(
    key: const Key('requestBanner'),
    warning: true,
    text:
        '@$name wants to chat. You will not see their messages until you accept. They will not be told whether you looked.',
    actions: [
      FilledButton(
        key: const Key('acceptRequest'),
        onPressed: busy ? null : onAccept,
        child: Text(busy ? 'Working…' : 'Accept'),
      ),
      OutlinedButton(
        key: const Key('blockRequest'),
        onPressed: busy ? null : onBlock,
        child: const Text('Block'),
      ),
      TextButton(
        key: const Key('reportRequest'),
        onPressed: busy ? null : onReport,
        child: const Text('Report'),
      ),
    ],
  );
}

/// A not-confirmed send whose warning could not be saved on disk, kept for this screen only.
class _MemoryPending {
  _MemoryPending(SendNotConfirmedException e)
    : messageId = e.messageId,
      body = e.body,
      chatId = e.chatId,
      sentAt = e.attemptedAt,
      outcome = e.outcome;
  final String messageId;
  final String body, chatId;
  final DateTime sentAt;
  SendOutcome outcome;

  LocalMessage asLocalMessage(AppSession? session) => LocalMessage(
    id: messageId,
    chatId: chatId,
    senderUid: session?.uid ?? '',
    senderDevice: session?.device.keys.deviceId ?? '',
    outgoing: true,
    sentAt: sentAt,
    body: body,
    status: outcome == SendOutcome.publishedLocalSaveFailed
        ? MessageStatus.ok
        : MessageStatus.unconfirmed,
  );
}

/// The warning under an outgoing message whose delivery is not known. It never shows a
/// sent or read tick, never invites a plain retry, and its actions cannot publish by accident.
class _UnconfirmedNote extends StatelessWidget {
  const _UnconfirmedNote({
    required this.messageId,
    required this.savedLocallyFailed,
    required this.action,
    required this.note,
    required this.onCheck,
    required this.onSendAgain,
    required this.onSave,
  });
  final String messageId;
  final bool savedLocallyFailed;
  final _MessageAction? action;
  final String? note;
  final VoidCallback onCheck;
  final VoidCallback onSendAgain;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final t = FireplaceUiTokens.of(context);
    final theme = Theme.of(context);
    final title = savedLocallyFailed
        ? 'Sent — could not save on this device'
        : 'Message not confirmed';
    final detail = savedLocallyFailed
        ? 'Your message was sent. Do not send it again.'
        : 'This message may have reached them. Sending it again could create a duplicate.';
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        key: ValueKey('unconfirmed-$messageId'),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 480),
        decoration: BoxDecoration(
          color: t.warningSurface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              liveRegion: true,
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 18, color: t.danger),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      title,
                      key: const Key('unconfirmedTitle'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(detail, style: theme.textTheme.bodySmall),
            if (note != null) ...[
              const SizedBox(height: 4),
              Text(
                note!,
                key: const Key('checkNote'),
                style: theme.textTheme.bodySmall,
              ),
            ],
            Wrap(
              children: [
                if (savedLocallyFailed)
                  TextButton(
                    key: const Key('saveOnDevice'),
                    onPressed: action == null ? onSave : null,
                    child: Text(
                      action == _MessageAction.saving
                          ? 'Saving…'
                          : 'Save on this device',
                    ),
                  )
                else ...[
                  TextButton(
                    key: const Key('checkSendStatus'),
                    onPressed: action == null ? onCheck : null,
                    child: Text(
                      action == _MessageAction.checking
                          ? 'Checking…'
                          : 'Check status',
                    ),
                  ),
                  TextButton(
                    key: const Key('resendUnconfirmed'),
                    onPressed: action == null ? onSendAgain : null,
                    child: Text(
                      action == _MessageAction.resending
                          ? 'Sending…'
                          : 'Send again…',
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NewDeviceBanner extends ConsumerStatefulWidget {
  const _NewDeviceBanner({required this.peerUid, required this.name});
  final String peerUid;
  final String name;
  @override
  ConsumerState<_NewDeviceBanner> createState() => _NewDeviceBannerState();
}

class _NewDeviceBannerState extends ConsumerState<_NewDeviceBanner> {
  bool _dismissed = false;
  @override
  Widget build(BuildContext context) {
    final fresh =
        ref.watch(newPeerDevicesProvider(widget.peerUid)).value ?? const [];
    if (fresh.isEmpty || _dismissed) return SizedBox.shrink();
    return UiNotice(
      key: const Key('newDeviceBanner'),
      warning: true,
      text:
          '${widget.name} added a new device. If this is unexpected, verify their security code.',
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  VerifyScreen(peerUid: widget.peerUid, peerName: widget.name),
            ),
          ),
          child: const Text('Verify'),
        ),
        TextButton(
          onPressed: () => setState(() => _dismissed = true),
          child: const Text('Dismiss'),
        ),
      ],
    );
  }
}

/// Shown while a contact's changed identity key is holding up their messages.

class _IdentityAlertBanner extends ConsumerWidget {
  const _IdentityAlertBanner({
    required this.peerUid,
    required this.name,
    required this.onReview,
    this.busy = false,
  });
  final String peerUid, name;
  final bool busy;
  final void Function(List<int> newIdentityPub) onReview;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pub = ref.watch(identityAlertsProvider).value?[peerUid];
    if (pub == null) return const SizedBox.shrink();
    return UiNotice(
      key: const Key('identityBanner'),
      warning: true,
      text:
          "@$name's security code changed. Messages are on hold until you review it.",
      actions: [
        TextButton(
          key: const Key('reviewIdentity'),
          onPressed: busy ? null : () => onReview(pub),
          child: Text(busy ? 'Reviewing…' : 'Review'),
        ),
      ],
    );
  }
}
