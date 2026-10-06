import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fireplace/src/crypto/device.dart';
import 'package:fireplace/src/crypto/session.dart';
import 'package:fireplace/src/model/keys/key_service.dart';
import 'package:fireplace/src/model/keys/prekey_service.dart';
import 'package:fireplace/src/model/safety/safety_service.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/db/secret_store.dart';
import 'package:fireplace/src/model/chat/message_limits.dart';
import 'package:fireplace/src/model/chat/async_mutex.dart';
import 'package:fireplace/src/model/chat/chat_exceptions.dart';
import 'package:fireplace/src/model/chat/session_store.dart';
import 'package:fireplace/src/model/chat/receive_journal.dart';
import 'package:fireplace/src/model/chat/identity_alerts.dart';
import 'package:fireplace/src/model/chat/chat_tuning.dart';

class MessageSender {
  MessageSender({
    required FirebaseFirestore db,
    required KeyService keys,
    required PreKeyService prekeys,
    required SecretStore secrets,
    required LocalMessageStore messages,
    SafetyService? safety,
    Future<void> Function(WriteBatch batch)? commitBatch,
    required String uid,
    required LocalDevice device,
    required AsyncMutex lock,
    required SessionStore sess,
    required ReceiveJournal journal,
    required IdentityAlerts alerts,
    required String Function(String chatId) peerOf,
    required Duration messageRetention,
  }) : this._(
         db,
         keys,
         prekeys,
         secrets,
         messages,
         safety,
         commitBatch,
         uid,
         device,
         lock,
         sess,
         journal,
         alerts,
         peerOf,
         messageRetention,
       );

  MessageSender._(
    this._db,
    this._keys,
    this._prekeys,
    this._secrets,
    this._messages,
    this._safety,
    this._commitBatch,
    this.uid,
    this.device,
    this._lock,
    this._sess,
    this._journal,
    this._alerts,
    this.peerOf,
    this.messageRetention,
  );

  final FirebaseFirestore _db;
  final KeyService _keys;
  final PreKeyService _prekeys;
  final SecretStore _secrets;
  final LocalMessageStore _messages;
  final SafetyService? _safety;
  final Future<void> Function(WriteBatch batch)? _commitBatch;
  final String uid;
  final LocalDevice device;
  final AsyncMutex _lock;
  final SessionStore _sess;
  final ReceiveJournal _journal;
  final IdentityAlerts _alerts;
  final String Function(String chatId) peerOf;
  final Duration messageRetention;

  Duration get sendGap => ChatTuning.sendGap;

  DateTime? _lastPublish;

  Future<void> sendText(String chatId, String text) {
    // Reject even if another send is waiting offline, without touching any state.
    if (messageTooLong(text)) {
      return Future.error(ChatException(messageLimitError));
    }
    return _sendText(chatId, text);
  }

  Future<void> _sendText(String chatId, String text) => _lock.run(() async {
    // A received message may have left a journal that was not fully applied. It holds a
    // snapshot of the session; replaying it AFTER this send would roll the ratchet back and
    // reuse a counter. So finish it first (if storage is still failing, the send fails
    // safely instead).
    await _journal.recoverJournals();
    final peerUid = peerOf(chatId);
    if (_safety?.isBlocked(peerUid) ?? false) {
      throw ChatException('You blocked this person. Unblock them to message.');
    }
    final chatRef = _db.collection('chats').doc(chatId);
    final chatData = (await chatRef.get()).data() ?? const {};
    final initiator = chatData['initiator'] as String?;
    final accepted = (chatData['accepted'] as bool?) ?? true;
    final sentInRequest = (chatData['requestCount'] as int?) ?? 0;
    // 'request'  : I started it and they have not accepted yet (max 3 messages)
    // 'accepting': they started it; replying accepts
    // 'normal'   : accepted (or created before requests existed)
    final mode = accepted
        ? 'normal'
        : (initiator == uid ? 'request' : 'accepting');
    if (mode == 'request' && sentInRequest >= ChatTuning.requestLimit) {
      throw ChatException(
        'Waiting for them to accept your message request before you can '
        'send more.',
      );
    }
    final List<DeviceBundle> peerDevices;
    try {
      peerDevices = await _keys.fetchDevices(peerUid);
    } on IdentityChangedException catch (e) {
      _alerts.set(e);
      rethrow;
    }
    if (peerDevices.isEmpty) {
      throw ChatException('This user has no active devices yet.');
    }
    final own = (await _keys.fetchDevices(uid))
        .where((d) => d.deviceId != device.keys.deviceId);
    final plain = utf8.encode(
      jsonEncode({
        'v': 1,
        'type': 'text',
        'body': text,
        'ts': DateTime.now().millisecondsSinceEpoch,
      }),
    );

    // Encrypt for every target but do NOT persist the advanced ratchets yet: if
    // publishing fails, the keys must not be consumed.
    final envelopes = <String, dynamic>{};
    final skipped = <String>[];
    final advanced = <(String, String, List<Session>)>[];
    for (final target in [...peerDevices, ...own]) {
      final sessions = await _sess.loadSessions(target.uid, target.deviceId);
      var preferred = SessionStore.pickSession(sessions);
      final stale =
          preferred != null &&
          !preferred.acknowledged &&
          DateTime.now().difference(preferred.createdAt) >
              ChatTuning.staleSessionAfter;
      if (preferred == null || stale) {
        try {
          final bundle = await _prekeys.fetchBundle(target);
          final (s, _) = await Session.initiate(
            local: device.keys,
            localBundle: device.bundle,
            remote: bundle,
          );
          sessions.add(s);
          preferred = s;
        } on PreKeyException catch (e) {
          // A device that never published prekeys (old install, never opened)
          // must not block delivery to the contact's other devices.
          if (preferred == null) {
            skipped.add(e.message);
            continue;
          }
          // otherwise keep using the older session
        }
        // forget long-dead unanswered sessions
        sessions.removeWhere(
          (x) =>
              x != preferred &&
              !x.acknowledged &&
              DateTime.now().difference(x.createdAt) > ChatTuning.pruneAfter,
        );
      }
      final env = await preferred.encrypt(plain, chatId: chatId);
      advanced.add((target.uid, target.deviceId, sessions));
      envelopes[target.deviceId] = env.toJson();
    }

    final reachedPeer = peerDevices.any(
      (d) => envelopes.containsKey(d.deviceId),
    );
    if (!reachedPeer) {
      throw ChatException(
        skipped.isNotEmpty
            ? skipped.first
            : 'This user has no active devices yet.',
      );
    }

    final ref = _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc();
    final sentAt = DateTime.now();
    final doc = {
      'senderUid': uid,
      'senderDevice': device.keys.deviceId,
      'ts': FieldValue.serverTimestamp(),
      'envelopes': envelopes,
      // The server copy is deleted 30 days after sending (Firestore TTL policy on this field).
      'expireAt': Timestamp.fromDate(DateTime.now().add(messageRetention)),
    };
    final lastBump = (chatData['lastMessageAt'] as Timestamp?)?.toDate();
    final bumpNow =
        lastBump == null ||
        DateTime.now().difference(lastBump) > const Duration(minutes: 1);

    Future<void> publish() async {
      // The message, this account's send clock (the rules' rate limit) and, for
      // requests, the chat state change all go in one atomic batch.
      final batch = _db.batch();
      batch.set(ref, doc);
      batch.set(
        _db.collection('users').doc(uid).collection('limits').doc('send'),
        {'at': FieldValue.serverTimestamp()},
      );
      if (mode != 'normal') {
        batch.update(chatRef, {
          'lastMessageAt': FieldValue.serverTimestamp(),
          if (mode == 'request') 'requestCount': FieldValue.increment(1),
          if (mode == 'accepting') 'accepted': true,
        });
      }
      await (_commitBatch ?? (b) => b.commit())(batch);
    }

    // Write-ahead: persist the advanced ratchets BEFORE publishing. If we published first
    // and the save then failed, the next message would be encrypted at a reused counter
    // under the same key. Saving first can at worst leave a harmless gap in the counter
    // (receivers tolerate gaps); a definitive publish failure rolls the state back.
    final undo = <(String, String, String?)>[];
    try {
      for (final (u, d, sessions) in advanced) {
        undo.add((u, d, await _secrets.read(_sess.sessKey(u, d))));
        await _sess.saveSessions(u, d, sessions);
      }
    } catch (_) {
      await _sess.restoreSessions(undo); // nothing was published
      rethrow;
    }

    // Stay under the server's pacing rule.
    final wait = _lastPublish == null
        ? Duration.zero
        : sendGap - DateTime.now().difference(_lastPublish!);
    if (wait > Duration.zero) await Future<void>.delayed(wait);
    try {
      try {
        await publish();
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied' || sendGap == Duration.zero) rethrow;
        // Could be the pacing rule (clock skew, a second device): wait and try once more.
        await Future<void>.delayed(const Duration(milliseconds: 900));
        await publish();
      }
      _lastPublish = DateTime.now();
    } on FirebaseException catch (e) {
      // These codes mean the batch definitely did NOT commit, so the counters were not
      // used and the stored ratchets can be put back. Anything else (network lost,
      // timeout) is ambiguous: the message may exist, so the advanced state stays.
      if (const {
        'permission-denied',
        'invalid-argument',
        'failed-precondition',
        'not-found',
        'already-exists',
        'resource-exhausted',
        'unauthenticated',
      }.contains(e.code)) {
        await _sess.restoreSessions(undo);
      }
      if (e.code == 'permission-denied') {
        throw ChatException(
          'This message could not be sent. You may be sending too fast, or the '
          'other person may have blocked you or is not accepting messages.',
        );
      }
      if (_definitelyNotPublished.contains(e.code)) {
        // The server refused the write, so nothing exists. Say so in plain words: a raw
        // FirebaseException would be shown as "may have reached them", which is wrong here.
        throw SendRefusedException(_refusedText(e.code));
      }
      // Anything else (network lost, timeout): the message may exist.
      throw await _unknownOutcome(chatId, ref.id, text, sentAt);
    } catch (_) {
      // A non-Firebase failure while publishing (for example a timeout) is ambiguous as well.
      throw await _unknownOutcome(chatId, ref.id, text, sentAt);
    }
    // Published. The ratchets were saved before publishing, so record the message.
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
        ),
      );
    } catch (_) {
      localSaveFailed = true;
    }
    if (mode == 'normal' && bumpNow) {
      // Keeps the chat list ordered; at most once a minute to save writes.
      try {
        await chatRef.update({'lastMessageAt': FieldValue.serverTimestamp()});
      } catch (_) {
        // Only affects chat-list ordering; the message itself is already sent.
      }
    }
    if (localSaveFailed) {
      // The message IS on the server. Say so, and do not let it look like a failure.
      throw SendNotConfirmedException(
        outcome: SendOutcome.publishedLocalSaveFailed,
        chatId: chatId,
        messageId: ref.id,
        body: text,
        attemptedAt: sentAt,
        persisted: false,
      );
    }
  });

  static String _refusedText(String code) => switch (code) {
    'resource-exhausted' => 'The server is busy or its free usage limit has been reached, so nothing was sent. Try again later.',
    'invalid-argument' => 'This message could not be sent (it may be too large), so nothing was sent. Try a shorter message.',
    'unauthenticated' =>
      'Your sign-in has expired, so nothing was sent. Sign in again and retry.',
    _ =>
      'This message could not be sent, so nothing was sent. Please try again.',
  };

  /// Error codes that mean the batch definitely did NOT commit.
  static const _definitelyNotPublished = {
    'permission-denied',
    'invalid-argument',
    'failed-precondition',
    'not-found',
    'already-exists',
    'resource-exhausted',
    'unauthenticated',
  };

  /// Keeps an "unconfirmed" entry in the encrypted on-device history (so the warning survives a
  /// restart) and returns the exception to throw. The advanced ratchet state is deliberately kept.
  Future<SendNotConfirmedException> _unknownOutcome(
    String chatId,
    String messageId,
    String body,
    DateTime sentAt,
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
    );
  }
}
