import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/chat/chat_exceptions.dart';
import 'package:fireplace/src/model/chat/chat_service.dart';
import 'package:fireplace/src/model/chat/message_controls.dart';
import 'package:fireplace/src/model/chat/pending_sends.dart';
import 'package:fireplace/src/model/keys/key_service.dart';

enum OutgoingState { sending, failed }

/// A message that has left the composer but is not in the history yet: it is
/// being sent, or the send failed and it waits for the person to decide.
@immutable
class OutgoingSend {
  const OutgoingSend({
    required this.id,
    required this.chatId,
    required this.body,
    required this.createdAt,
    this.replyTarget,
    this.state = OutgoingState.sending,
    this.error,
    this.mayHaveArrived = false,
    this.identity,
    this.historyKnown = false,
    this.historyIds = const {},
  });

  /// Local only; never a server message id.
  final String id;
  final String chatId, body;
  final String? replyTarget;
  final DateTime createdAt;
  final OutgoingState state;

  /// Plain words for the person, set when [state] is failed.
  final String? error;

  /// The failure was not a clear refusal, so a copy may have been delivered.
  final bool mayHaveArrived;

  /// Set when the send stopped because the contact's security code changed.
  final IdentityChangedException? identity;

  /// True when [historyIds] is the conversation as it was when this send was
  /// queued. A later stored message with the same text is this send, so the
  /// optimistic row must not be drawn beside it. False when that snapshot
  /// was not loaded yet; the optimistic row then stays up.
  final bool historyKnown;

  /// Message ids already on screen when this send was queued.
  final Set<String> historyIds;

  OutgoingSend _failed(
    String error, {
    bool mayHaveArrived = false,
    IdentityChangedException? identity,
  }) => OutgoingSend(
    id: id,
    chatId: chatId,
    body: body,
    createdAt: createdAt,
    replyTarget: replyTarget,
    state: OutgoingState.failed,
    error: error,
    mayHaveArrived: mayHaveArrived,
    identity: identity,
    historyKnown: historyKnown,
    historyIds: historyIds,
  );

  OutgoingSend _retrying() => OutgoingSend(
    id: id,
    chatId: chatId,
    body: body,
    createdAt: createdAt,
    replyTarget: replyTarget,
    historyKnown: historyKnown,
    historyIds: historyIds,
  );
}

/// Sends messages one at a time per conversation, in the order they were
/// written, and keeps the ones that failed until the person sends them again
/// or deletes them. It lives above the conversation screen, so leaving the
/// screen neither stops a send nor loses a failed message.
///
/// Account-scoped memory only: nothing here is written to disk or the server,
/// and nothing is ever sent again without being asked.
class OutgoingSends extends Notifier<List<OutgoingSend>> {
  static const uncertainText =
      'We could not confirm this send. It may have reached them. Check your history before sending again.';
  static const identityText =
      'Their security code changed, so nothing was sent. Review it, then send again.';
  static const signedOutText =
      'You are not signed in, so nothing was sent. Sign in and send again.';

  int _next = 0;
  Object _generation = Object();
  final _draining = <String>{};

  @override
  List<OutgoingSend> build() {
    ref.watch(appSessionProvider.select((s) => s.value?.uid));
    _generation = Object();
    _draining.clear();
    return const [];
  }

  /// Takes the message from the composer and starts sending it.
  String enqueue(String chatId, String body, {String? replyTarget}) {
    final history = ref.read(messagesProvider(chatId));
    final send = OutgoingSend(
      id: 'outgoing-${_next++}',
      chatId: chatId,
      body: body,
      replyTarget: replyTarget,
      createdAt: ref.read(messageControlNowProvider)(),
      historyKnown: history.value != null,
      historyIds: history.value == null
          ? const <String>{}
          : Set<String>.unmodifiable(history.value!.map((m) => m.id)),
    );
    state = [...state, send];
    _drain(chatId);
    return send.id;
  }

  /// The person's explicit decision to send a failed message again.
  void sendAgain(String id) {
    final send = _find(id);
    if (send == null || send.state != OutgoingState.failed) return;
    _replace(send._retrying());
    _drain(send.chatId);
  }

  /// Gives up on a failed message. One that is being sent cannot be recalled.
  void delete(String id) {
    final send = _find(id);
    if (send == null || send.state != OutgoingState.failed) return;
    _remove(id);
  }

  /// Waits for a frame that is already due. Does nothing when no Flutter
  /// binding is up, or when no frame is scheduled.
  Future<void> _showBeforeSending() async {
    final SchedulerBinding scheduler;
    try {
      scheduler = SchedulerBinding.instance;
    } catch (_) {
      return;
    }
    final frameDue =
        scheduler.schedulerPhase != SchedulerPhase.idle ||
        scheduler.hasScheduledFrame;
    if (!frameDue) return;
    await scheduler.endOfFrame;
  }

  OutgoingSend? _find(String id) => state.where((s) => s.id == id).firstOrNull;
  void _replace(OutgoingSend next) => state = [
    for (final s in state)
      if (s.id == next.id) next else s,
  ];
  void _remove(String id) => state = [
    for (final s in state)
      if (s.id != id) s,
  ];

  Future<void> _drain(String chatId) async {
    if (!_draining.add(chatId)) return;
    final generation = _generation;
    final uid = ref.read(appSessionProvider).value?.uid;
    bool current() =>
        ref.mounted &&
        identical(generation, _generation) &&
        ref.read(appSessionProvider).value?.uid == uid;
    try {
      // Each pass takes one waiting message out of the waiting state, so the
      // loop ends when none is left.
      while (current()) {
        final send = state
            .where(
              (s) => s.chatId == chatId && s.state == OutgoingState.sending,
            )
            .firstOrNull;
        if (send == null) return;
        final service = ref.read(appSessionProvider).value?.chat;
        if (service == null) {
          _replace(send._failed(signedOutText));
          continue;
        }
        // Encryption runs on this isolate. Let the row and the empty
        // composer paint first. A unit test has no binding or no frame, and
        // endOfFrame would stall it, so that case sends immediately.
        await _showBeforeSending();
        if (!current()) return;
        try {
          if (send.replyTarget == null) {
            await service.sendText(chatId, send.body);
          } else {
            await service.sendReply(chatId, send.body, send.replyTarget!);
          }
          if (!current()) return;
          // It is in the history now and shows from there.
          _remove(send.id);
        } on SendNotConfirmedException catch (e) {
          if (!current()) return;
          // It may have been delivered: the history (or, if that could not be
          // written, the in-memory record) shows it with its own warning and
          // its own "check" and "send another copy" decisions.
          if (!e.persisted) {
            ref.read(pendingLocalSendsProvider.notifier).add(e, ownerUid: uid!);
          }
          _remove(send.id);
        } on IdentityChangedException catch (e) {
          if (!current()) return;
          _replace(send._failed(identityText, identity: e));
        } on ChatException catch (e) {
          if (!current()) return;
          _replace(send._failed(e.message));
        } catch (_) {
          if (!current()) return;
          _replace(send._failed(uncertainText, mayHaveArrived: true));
        }
      }
    } finally {
      // Signing back into the same account still starts a new queue. An old
      // completion must neither resume that queue nor unlock its active send.
      if (identical(generation, _generation)) _draining.remove(chatId);
    }
  }
}

final outgoingSendsProvider =
    NotifierProvider<OutgoingSends, List<OutgoingSend>>(OutgoingSends.new);
