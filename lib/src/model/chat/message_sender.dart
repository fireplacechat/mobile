import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:fireplace/src/crypto/device.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/db/message_mutation.dart';
import 'package:fireplace/src/db/message_quote.dart';
import 'package:fireplace/src/model/chat/async_mutex.dart';
import 'package:fireplace/src/model/chat/chat_exceptions.dart';
import 'package:fireplace/src/model/chat/chat_tuning.dart';
import 'package:fireplace/src/model/chat/envelope_encryption.dart';
import 'package:fireplace/src/model/chat/identity_alerts.dart';
import 'package:fireplace/src/model/chat/message_content.dart';
import 'package:fireplace/src/model/chat/message_limits.dart';
import 'package:fireplace/src/model/chat/message_payload.dart';
import 'package:fireplace/src/model/chat/publish_errors.dart';
import 'package:fireplace/src/model/chat/receive_journal.dart';
import 'package:fireplace/src/model/chat/send_allowance.dart';
import 'package:fireplace/src/model/chat/send_mode.dart';
import 'package:fireplace/src/model/chat/session_store.dart';
import 'package:fireplace/src/model/keys/key_service.dart';
import 'package:fireplace/src/model/keys/prekey_service.dart';
import 'package:fireplace/src/model/safety/safety_service.dart';

/// Sends messages and controls (reactions, edits, deletes). One send, under
/// the session lock:
///
/// 1. finish any open receive journal, then prepare the content;
/// 2. check the chat allows it ([SendMode]);
/// 3. encrypt for the peer's and this account's other devices
///    ([encryptForDevices]);
/// 4. save the advanced ratchets ahead of publishing
///    ([SessionStore.saveAhead]);
/// 5. publish one batch, paced for the server's rate rule;
/// 6. record the message in local history.
///
/// A definite refusal puts the ratchets back and says nothing was sent. An
/// ambiguous failure keeps them and records the message as unconfirmed; it is
/// never resent automatically.
class MessageSender {
  MessageSender({
    required this._db,
    required KeyService keys,
    required this._prekeys,
    required this._messages,
    this._safety,
    Future<void> Function(WriteBatch batch)? commitBatch,
    this._beforeChatListBump,
    Future<List<DeviceBundle>> Function(String uid)? devices,
    this._knownChat,
    required this.uid,
    required this.device,
    required this._lock,
    required this._sess,
    required this._journal,
    required this._alerts,
    required this.peerOf,
    required this.messageRetention,
  }) : _commitBatch = commitBatch ?? ((b) => b.commit()),
       _devicesOf = devices ?? keys.fetchDevices;

  final FirebaseFirestore _db;
  final PreKeyService _prekeys;
  final LocalMessageStore _messages;
  final SafetyService? _safety;
  final Future<void> Function(WriteBatch batch) _commitBatch;
  final Future<void> Function()? _beforeChatListBump;
  final Future<List<DeviceBundle>> Function(String uid) _devicesOf;
  final Map<String, dynamic>? Function(String chatId)? _knownChat;
  final String uid;
  final LocalDevice device;
  final AsyncMutex _lock;
  final SessionStore _sess;
  final ReceiveJournal _journal;
  final IdentityAlerts _alerts;
  final String Function(String chatId) peerOf;
  final Duration messageRetention;

  final _allowance = SendAllowance();

  /// When this device last started a chat-list bump. The server timestamp can
  /// still be the old one when the next message is sent, and a second bump
  /// would only repeat a write.
  DateTime? _lastListBump;

  Future<void> sendText(String chatId, String text) {
    // Reject even if another send is waiting offline, without touching any state.
    if (messageTooLong(text)) {
      return Future.error(ChatException(messageLimitError));
    }
    return _send(chatId, text);
  }

  Future<void> sendReply(String chatId, String text, String targetId) =>
      _send(chatId, text, replyTarget: targetId);

  Future<void> sendQuoted(String chatId, String text, MessageQuote quote) =>
      _send(chatId, text, quote: quote);

  Future<void> sendControl(String chatId, MessageMutation mutation) =>
      _send(chatId, '', mutation: mutation);

  Future<void> _send(
    String chatId,
    String text, {
    MessageMutation? mutation,
    MessageQuote? quote,
    String? replyTarget,
  }) => _lock.run(() async {
    // 1. A received message may have left a journal that was not fully applied. It holds a
    // snapshot of the session; replaying it AFTER this send would roll the ratchet back and
    // reuse a counter. So finish it first (if storage is still failing, the send fails
    // safely instead).
    await _journal.recoverJournals();
    final content = await prepareMessageContent(
      messages: _messages,
      uid: uid,
      chatId: chatId,
      text: text,
      quote: quote,
      mutation: mutation,
      replyTarget: replyTarget,
    );
    quote = content.quote;
    mutation = content.mutation;
    final peerUid = peerOf(chatId);
    if (_safety?.isBlocked(peerUid) ?? false) {
      throw ChatException('You blocked this person. Unblock them to message.');
    }

    // 2. What the chat allows.
    final chatRef = _db.collection('chats').doc(chatId);
    final chat = await _chatState(chatId, chatRef);
    final mode = SendMode.check(
      chat,
      uid: uid,
      changesMessage: mutation != null || quote != null,
    );

    // 3. Encrypt for every device.
    final List<DeviceBundle> peerDevices;
    try {
      peerDevices = await _devicesOf(peerUid);
    } on IdentityChangedException catch (e) {
      _alerts.set(e);
      rethrow;
    }
    if (peerDevices.isEmpty) {
      throw ChatException('This user has no active devices yet.');
    }
    final own = (await _devicesOf(uid))
        .where((d) => d.deviceId != device.keys.deviceId);
    final sealed = await encryptForDevices(
      sessions: _sess,
      prekeys: _prekeys,
      device: device,
      targets: [...peerDevices, ...own],
      plain: encodeMessagePayload(
        text: text,
        now: DateTime.now(),
        quote: quote,
        mutation: mutation,
      ),
      chatId: chatId,
    );
    if (!peerDevices.any((d) => sealed.envelopes.containsKey(d.deviceId))) {
      throw ChatException(
        sealed.skipped.isNotEmpty
            ? sealed.skipped.first
            : 'This user has no active devices yet.',
      );
    }

    final ref = chatRef.collection('messages').doc();
    final sentAt = DateTime.now();
    final doc = {
      'senderUid': uid,
      'senderDevice': device.keys.deviceId,
      'ts': FieldValue.serverTimestamp(),
      'envelopes': sealed.envelopes,
      // The server copy is deleted 30 days after sending (Firestore TTL policy on this field).
      'expireAt': Timestamp.fromDate(DateTime.now().add(messageRetention)),
    };
    final lastBump = (chat['lastMessageAt'] as Timestamp?)?.toDate();

    // 4. Save ahead, then 5. publish.
    final undo = await _sess.saveAhead(sealed.advanced);
    try {
      await _publishPaced(ref, doc, chatRef, mode);
    } on FirebaseException catch (e) {
      if (!definitelyNotPublished.contains(e.code)) {
        // Network lost, timeout: the message may exist.
        throw await _unknownOutcome(
          chatId,
          ref.id,
          text,
          sentAt,
          mutation,
          quote,
        );
      }
      // Nothing was committed, so the counters were not used.
      await _sess.restoreSessions(undo);
      if (e.code == 'permission-denied') {
        throw ChatException(permissionDeniedText);
      }
      // A raw FirebaseException would be shown as "may have reached them",
      // which is wrong here.
      throw SendRefusedException(refusedText(e.code));
    } catch (_) {
      // A non-Firebase failure while publishing (for example a timeout) is ambiguous as well.
      throw await _unknownOutcome(
        chatId,
        ref.id,
        text,
        sentAt,
        mutation,
        quote,
      );
    }

    // 6. Published. The ratchets were saved before publishing, so record the message.
    var localSaveFailed = false;
    try {
      await _messages.add(
        LocalMessage(
          id: ref.id,
          chatId: chatId,
          senderUid: uid,
          senderDevice: device.keys.deviceId,
          outgoing: true,
          sentAt: sentAt,
          body: text,
          mutation: mutation,
          quote: quote,
        ),
      );
    } catch (_) {
      localSaveFailed = true;
    }
    _maybeOrderChatList(chatRef, mode, lastBump);
    if (localSaveFailed) {
      // The message IS on the server. Say so, and do not let it look like a failure.
      throw SendNotConfirmedException(
        outcome: SendOutcome.publishedLocalSaveFailed,
        chatId: chatId,
        messageId: ref.id,
        body: text,
        attemptedAt: sentAt,
        persisted: false,
        mutation: mutation,
        quote: quote,
      );
    }
  });

  /// The chat document's fields. A chat can become accepted but never go
  /// back, so an accepted copy from the chat-list listener is final and saves
  /// a read. A request is read fresh: its counter decides whether this
  /// message may be sent at all.
  Future<Map<String, dynamic>> _chatState(
    String chatId,
    DocumentReference<Map<String, dynamic>> chatRef,
  ) async {
    final known = _knownChat?.call(chatId);
    if (known != null && (known['accepted'] as bool? ?? true)) return known;
    return (await chatRef.get()).data() ?? const {};
  }

  /// Publishes the message, this account's send clock (the rules' rate
  /// limit) and, for requests, the chat change, in one atomic batch.
  ///
  /// The clock form comes from [SendAllowance]. A refused clock may be a
  /// wrong guess (another device opened a window, the clocks differ), so the
  /// other form is tried at once. If the server refuses both, it may still
  /// be on the older rule: the older form is tried after its gap, and used
  /// from then on. A refusal for another reason (a block) fails every form
  /// and is reported as before.
  Future<void> _publishPaced(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, Object> doc,
    DocumentReference<Map<String, dynamic>> chatRef,
    SendMode mode,
  ) async {
    final limit = _db
        .collection('users')
        .doc(uid)
        .collection('limits')
        .doc('send');
    Future<void> publish(SendClock clock) {
      final at = FieldValue.serverTimestamp();
      final batch = _db.batch()..set(ref, doc);
      switch (clock) {
        case SendClock.open:
          batch.set(limit, {'at': at, 'window': at, 'sent': 1});
        case SendClock.next:
          batch.update(limit, {'at': at, 'sent': FieldValue.increment(1)});
        case SendClock.legacy:
          batch.set(limit, {'at': at});
      }
      final change = mode.chatChange;
      if (change != null) batch.update(chatRef, change);
      return _commitBatch(batch);
    }

    bool refused(FirebaseException e) =>
        ChatTuning.pacing &&
        (e.code == 'permission-denied' || e.code == 'not-found');

    final wait = _allowance.wait;
    if (wait > Duration.zero) await Future<void>.delayed(wait);
    final startedAt = DateTime.now();
    var clock = _allowance.next;
    try {
      await publish(clock);
    } on FirebaseException catch (e) {
      if (!refused(e)) rethrow;
      if (clock == SendClock.legacy) {
        await Future<void>.delayed(const Duration(milliseconds: 900));
      } else {
        clock = clock.other;
        try {
          await publish(clock);
          _allowance.published(clock, startedAt);
          return;
        } on FirebaseException catch (e) {
          if (!refused(e)) rethrow;
          clock = SendClock.legacy;
          await Future<void>.delayed(ChatTuning.legacySendGap);
        }
      }
      await publish(clock);
    }
    _allowance.published(clock, startedAt);
  }

  /// Moves the chat up the chat list at most once a minute. Requests already
  /// did that in their batch. The saved message is already in the
  /// conversation, so this is not awaited: waiting kept the row on screen
  /// twice, from history and from the pending send, for the whole round trip.
  /// It never decides whether the send succeeded.
  void _maybeOrderChatList(
    DocumentReference<Map<String, dynamic>> chatRef,
    SendMode mode,
    DateTime? lastBump,
  ) {
    const quiet = Duration(minutes: 1);
    final now = DateTime.now();
    final serverQuiet = lastBump == null || now.difference(lastBump) > quiet;
    final localQuiet =
        _lastListBump == null || now.difference(_lastListBump!) > quiet;
    if (mode != SendMode.normal || !serverQuiet || !localQuiet) return;
    _lastListBump = now;
    unawaited(() async {
      try {
        await _beforeChatListBump?.call();
        await chatRef.update({'lastMessageAt': FieldValue.serverTimestamp()});
      } catch (_) {
        // Only affects chat-list ordering; the message itself is already sent.
      }
    }());
  }

  /// Keeps an "unconfirmed" entry in the encrypted on-device history (so the warning survives a
  /// restart) and returns the exception to throw. The advanced ratchet state is deliberately kept.
  Future<SendNotConfirmedException> _unknownOutcome(
    String chatId,
    String messageId,
    String body,
    DateTime sentAt,
    MessageMutation? mutation,
    MessageQuote? quote,
  ) async {
    var persisted = true;
    try {
      await _messages.add(
        LocalMessage(
          id: messageId,
          chatId: chatId,
          senderUid: uid,
          senderDevice: device.keys.deviceId,
          outgoing: true,
          sentAt: sentAt,
          body: body,
          status: MessageStatus.unconfirmed,
          mutation: mutation,
          quote: quote,
        ),
      );
    } catch (_) {
      persisted = false;
    }
    return SendNotConfirmedException(
      outcome: SendOutcome.publishUnknown,
      chatId: chatId,
      messageId: messageId,
      body: body,
      attemptedAt: sentAt,
      persisted: persisted,
      mutation: mutation,
      quote: quote,
    );
  }
}
