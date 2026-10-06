import 'package:fireplace/src/model/chat/chat_directory.dart';
import 'package:fireplace/src/model/chat/session_store.dart';
// ignore_for_file: prefer_initializing_formals
import 'package:fireplace/src/model/chat/async_mutex.dart';
import 'package:fireplace/src/model/chat/chat_exceptions.dart';
import 'package:fireplace/src/model/chat/chat_summary.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:fireplace/src/crypto/device.dart';
import 'package:fireplace/src/crypto/session.dart';
import 'package:fireplace/src/model/keys/key_service.dart';
import 'package:fireplace/src/model/keys/prekey_service.dart';
import 'package:fireplace/src/model/safety/safety_service.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/db/secret_store.dart';
import 'package:fireplace/src/model/chat/message_limits.dart';

export 'package:fireplace/src/model/chat/chat_exceptions.dart';
export 'package:fireplace/src/model/chat/chat_summary.dart';

/// Encrypts/decrypts messages and moves ciphertext through Firestore.
/// Plaintext never leaves this class except into the on-device [LocalMessageStore].
/// How long the server keeps a message. Each message carries an `expireAt` this far ahead, and a
/// Firestore TTL policy on that field deletes it. Messages live on in the recipients' own phones.
const messageRetention = Duration(days: 30);

class ChatService {
  ChatService({
    required FirebaseFirestore db,
    required this.uid,
    required this.device,
    required KeyService keys,
    required PreKeyService prekeys,
    required SecretStore secrets,
    required LocalMessageStore messages,
    SafetyService? safety,
    @visibleForTesting Future<void> Function(WriteBatch batch)? commitBatch,
  }) : _db = db,
       _keys = keys,
       _prekeys = prekeys,
       _secrets = secrets,
       _messages = messages,
       _safety = safety,
       _sess = SessionStore(secrets, device),
       _directory = ChatDirectory(db, messages, uid, safety),
       _commitBatch = commitBatch {
    keys.bindLocalDevice(uid, device);
  }

  final FirebaseFirestore _db;
  final String uid;
  final LocalDevice device;
  final KeyService _keys;
  final PreKeyService _prekeys;
  final SafetyService? _safety;
  final Future<void> Function(WriteBatch batch)? _commitBatch;
  final SecretStore _secrets;
  final LocalMessageStore _messages;
  final SessionStore _sess;
  final ChatDirectory _directory;
  final AsyncMutex _lock = AsyncMutex(); // serializes all session-state changes

  bool _closed = false;
  Future<void>? _closing;
  final _syncCancels = <Future<void> Function()>{};
  final _receiveWork = <Future<void>>{};

  void _trackReceive(Future<void> work) {
    final guarded = work.catchError((Object _) {});
    _receiveWork.add(guarded);
    unawaited(guarded.then((_) => _receiveWork.remove(guarded)));
  }

  /// Stop scheduling receives and drain work before local session storage closes.
  Future<void> close() => _closing ??= () async {
    _closed = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    for (final cancel in _syncCancels.toList()) {
      await cancel();
    }
    while (_receiveWork.isNotEmpty) {
      await Future.wait(_receiveWork.toList());
    }
    await _lock.run(() async {});
    _deferred.clear();
    _unfinished.clear();
    unawaited(_alertCtrl.close());
  }();

  static String chatIdFor(String a, String b) => ChatDirectory.chatIdFor(a, b);

  String peerOf(String chatId) => _directory.peerOf(chatId);

  Future<String> startChat(String username) => _directory.startChat(username);

  Future<void> acceptRequest(String chatId) => _directory.acceptRequest(chatId);

  Stream<List<ChatSummary>> watchChats() => _directory.watchChats();

  Future<bool> removeChatIfPeerDeleted(String chatId) =>
      _directory.removeChatIfPeerDeleted(chatId);

  Future<String?> usernameOf(String peerUid) => _directory.usernameOf(peerUid);

  Stream<List<LocalMessage>> watchMessages(String chatId) =>
      _messages.watch(chatId);

  // ----------------------------------------------------------------- sessions

  // -------------------------------------------------------------------- send

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
    await _recoverJournals();
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
    if (mode == 'request' && sentInRequest >= requestLimit) {
      throw ChatException(
        'Waiting for them to accept your message request before you can '
        'send more.',
      );
    }
    final List<DeviceBundle> peerDevices;
    try {
      peerDevices = await _keys.fetchDevices(peerUid);
    } on IdentityChangedException catch (e) {
      _setAlert(e);
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
      var preferred = pickSession(sessions);
      final stale =
          preferred != null &&
          !preferred.acknowledged &&
          DateTime.now().difference(preferred.createdAt) > staleSessionAfter;
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
              DateTime.now().difference(x.createdAt) > _pruneAfter,
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

  /// Asks the SERVER whether an unconfirmed message exists. Only server evidence counts: a
  /// missing document, an offline error or a cached answer never proves it was not published.
  /// Never publishes anything. When the server holds it, local history is repaired.
  Future<SendOutcome> checkSendStatus(String chatId, String messageId) async {
    peerOf(chatId);
    final ref = _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId);
    final DocumentSnapshot<Map<String, dynamic>> snap;
    try {
      snap = await ref.get(const GetOptions(source: Source.server));
    } catch (_) {
      return SendOutcome.publishUnknown;
    }
    final data = snap.data();
    if (!snap.exists ||
        snap.metadata.isFromCache ||
        data == null ||
        data['senderUid'] != uid ||
        data['senderDevice'] != device.keys.deviceId) {
      return SendOutcome.publishUnknown;
    }
    try {
      await _confirmOwnSend(chatId, messageId);
    } catch (_) {
      // The server holds it, so it IS confirmed; the entry is repaired by the next check or sync.
    }
    return SendOutcome.confirmed;
  }

  /// Turns our own "unconfirmed" entry into an ordinary sent message. Throws if the local write
  /// fails: during sync that defers the message and holds the cursor, like any other storage
  /// trouble, so the warning is always resolved eventually.
  Future<void> _confirmOwnSend(String chatId, String messageId) async {
    final m = await _messages.get(chatId, messageId);
    if (m != null && m.status == MessageStatus.unconfirmed) {
      await _messages.add(
        LocalMessage(
          id: m.id,
          chatId: m.chatId,
          senderUid: m.senderUid,
          senderDevice: m.senderDevice,
          outgoing: true,
          sentAt: m.sentAt,
          body: m.body,
        ),
      );
    }
  }

  /// Writes a message that is KNOWN to be on the server into this device's history (repairs a
  /// failed local save). No server write and no ratchet change.
  Future<void> saveSentLocally({
    required String chatId,
    required String messageId,
    required String body,
    required DateTime sentAt,
  }) => _messages.add(
    LocalMessage(
      id: messageId,
      chatId: chatId,
      senderUid: uid,
      senderDevice: device.keys.deviceId,
      outgoing: true,
      sentAt: sentAt,
      body: body,
    ),
  );

  /// The explicit "send another copy" decision. The original may already have been delivered, so
  /// this is a NEW message: new id, ratchets advanced normally (old counters are never reused).
  /// The warning for the original is removed afterwards.
  Future<void> resendUnconfirmed({
    required String chatId,
    required String messageId,
    required String body,
  }) async {
    await sendText(chatId, body);
    try {
      await _messages.remove(chatId, messageId);
    } catch (_) {
      // The old warning may linger; it is only a warning.
    }
  }

  // ----------------------------------------------------------------- receive

  static const requestLimit = 3;

  /// A session we started that the peer never answered for this long is considered
  /// possibly lost (for example the peer lost the matching prekey), so the next send
  /// starts a fresh handshake as well. Old sessions stay, so late replies still work.
  static Duration staleSessionAfter = const Duration(hours: 24);
  static const _pruneAfter = Duration(days: 30);

  static Session? pickSession(List<Session> sessions) =>
      SessionStore.pickSession(sessions);

  /// Minimum time between two sends from this device. The server enforces 500 ms
  /// per account across all chats; this stays safely above it so honest use never
  /// trips the rule. Tests set it to zero (test/flutter_test_config.dart).
  static Duration sendGap = const Duration(milliseconds: 700);
  DateTime? _lastPublish;
  static const _pageCap = 500;

  /// Test hooks: how many query pages each chat's sync has opened, and which documents each
  /// snapshot delivered. Used to assert that paging makes progress and does not re-read.
  @visibleForTesting
  final Map<String, int> syncPagesOpened = {};
  @visibleForTesting
  void Function(String chatId, List<String> ids)? syncObserver;

  /// Messages that could not be processed yet (identity change awaiting the
  /// user, or a transient storage/network error). See [retryDeferred].
  final Map<String, ({String chatId, String msgId, Map<String, dynamic> data})>
  _deferred = {};
  final Map<String, List<int>> _identityAlerts = {};
  final _alertCtrl = StreamController<Map<String, List<int>>>.broadcast();
  Timer? _retryTimer;
  DateTime? _lastRepair;

  /// A peer used a prekey we cannot answer: drop orphaned published prekeys and
  /// refill the pool (at most once a minute, in the background).
  void _repairPrekeys() {
    if (_closed) return;
    final now = DateTime.now();
    if (_lastRepair != null &&
        now.difference(_lastRepair!) < const Duration(minutes: 1)) {
      return;
    }
    _lastRepair = now;
    _trackReceive(_prekeys.maintain(uid, device));
  }

  /// Contacts whose changed identity is blocking messages, with the NEW identity key.
  Map<String, List<int>> get identityAlerts =>
      Map.unmodifiable(_identityAlerts);
  Set<String> get identityAlertPeers => _identityAlerts.keys.toSet();

  Stream<Map<String, List<int>>> watchIdentityAlerts() => Stream.multi((sink) {
    // Subscribe before delivering the initial snapshot. An alert arriving while
    // that snapshot is delivered/paused must not disappear between yield/yield*.
    final sub = _alertCtrl.stream.listen(
      sink.add,
      onError: sink.addError,
      onDone: sink.close,
    );
    sink.onCancel = sub.cancel;
    sink.add(identityAlerts);
  });

  void _setAlert(IdentityChangedException e) {
    _identityAlerts[e.peerUid] = e.newIdentityPub;
    _alertCtrl.add(identityAlerts);
  }

  /// Messages the listener has seen but not yet finished (being processed, or waiting for a
  /// retry). The sync cursor must never move past the oldest of these: the retry list is
  /// in memory only, so after a restart the cursor is the only thing that brings them back.
  /// A null timestamp blocks all advancing until the message is done.
  final Map<String, ({String chatId, Timestamp? ts})> _unfinished = {};

  String _cursorKey(String chatId) => 'cursor:${device.keys.deviceId}:$chatId';

  Future<Timestamp?> _cursor(String chatId) async {
    final raw = await _secrets.read(_cursorKey(chatId));
    if (raw == null) return null;
    final parts = raw.split(':');
    if (parts.length != 2) return null;
    final sec = int.tryParse(parts[0]), ns = int.tryParse(parts[1]);
    return sec == null || ns == null ? null : Timestamp(sec, ns);
  }

  Future<void> _advanceCursor(String chatId, Timestamp to) async {
    final cur = await _cursor(chatId);
    if (cur != null && cur.compareTo(to) >= 0) return;
    await _secrets.write(_cursorKey(chatId), '${to.seconds}:${to.nanoseconds}');
  }

  /// Decrypts new messages of a chat. The first run looks at the newest
  /// [limit] messages; afterwards it resumes from a persisted cursor, so
  /// everything received while the app was closed is fetched, however many.
  ///
  /// Two different positions are kept apart on purpose:
  ///  * the durable **cursor** (see [_advanceCursor]) is a recovery watermark: it never passes a
  ///    message that is not finished, so that after a restart unfinished messages are re-read;
  ///  * the **page position** (`pageAfter`, in memory only) is where the NEXT page of a long
  ///    backlog starts. It always moves to just after the last document of the page just read, so
  ///    every page makes progress, even when the cursor is held back by a message that is waiting
  ///    for a retry, and even when 500 or more messages share one timestamp. Unfinished messages
  ///    are retried from memory by [retryDeferred], not by re-reading them.
  StreamSubscription<void> startSync(String chatId, {int limit = 50}) {
    if (_closed) throw StateError('Chat service is closed.');
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? inner;
    var cancelled = false;
    var generation = 0;
    DocumentSnapshot<Map<String, dynamic>>? pageAfter;
    final done = StreamController<void>();
    final col = _db.collection('chats').doc(chatId).collection('messages');

    Future<void> listen() async {
      if (cancelled || _closed) return;
      final mine = ++generation;
      final cursor = await _cursor(chatId);
      if (cancelled || _closed || mine != generation) return;
      Query<Map<String, dynamic>> q;
      if (cursor == null) {
        q = col.orderBy('ts', descending: true).limit(limit);
      } else {
        q = col.where('ts', isGreaterThanOrEqualTo: cursor).orderBy('ts');
        // Continue after the last document already read (ties on `ts` are broken by document
        // id), never from the cursor again.
        if (pageAfter != null) q = q.startAfterDocument(pageAfter!);
        q = q.limit(_pageCap);
      }
      syncPagesOpened[chatId] = (syncPagesOpened[chatId] ?? 0) + 1;
      inner = q.snapshots().listen((snap) {
        _trackReceive(() async {
          if (cancelled || _closed || mine != generation) return;
          final added =
              snap.docChanges
                  .where((c) => c.type == DocumentChangeType.added)
                  .map((c) => c.doc)
                  .toList()
                ..sort((a, b) => _ts(a).compareTo(_ts(b)));
          syncObserver?.call(chatId, [for (final d in added) d.id]);
          Timestamp? advanceTo;
          var blocked = false;
          // Register the whole batch first, synchronously: another batch's callback may run
          // while this one waits on the lock, and must see these as unfinished.
          for (final d in added) {
            final t = d.data()?['ts'];
            _unfinished['$chatId/${d.id}'] = (
              chatId: chatId,
              ts: t is Timestamp ? t : null,
            );
          }
          for (final d in added) {
            if (cancelled || _closed || mine != generation) return;
            final ok = await _handle(chatId, d.id, d.data()!);
            if (!ok) blocked = true;
            final ts = d.data()!['ts'];
            // Never advance past a message we still owe a retry.
            if (!blocked && ts is Timestamp) advanceTo = ts;
          }
          if (advanceTo != null) {
            // Never move past a message that is not finished (see [_unfinished]). Re-reading
            // from the oldest unfinished message's own timestamp is safe: stored messages are
            // skipped.
            for (final u in _unfinished.values) {
              if (u.chatId != chatId) continue;
              final ts = u.ts;
              if (ts == null) {
                advanceTo = null;
                break;
              }
              if (advanceTo != null && ts.compareTo(advanceTo) < 0) {
                advanceTo = ts;
              }
            }
          }
          if (advanceTo != null &&
              !cancelled &&
              !_closed &&
              mine == generation) {
            try {
              await _advanceCursor(chatId, advanceTo);
            } catch (_) {
              // Only an optimisation: without it the next run re-reads these messages, and
              // messages already stored are skipped. Must not escape the listener.
            }
          }
          if (cursor != null &&
              snap.docs.length >= _pageCap &&
              !cancelled &&
              !_closed &&
              mine == generation) {
            // More backlog: the next page starts right after this one.
            pageAfter = snap.docs.last;
            await inner?.cancel();
            await listen();
          }
        }());
      }, onError: (_) {});
    }

    final subscription = done.stream.listen(null);
    final cancel = subscription.cancel;
    _syncCancels.add(cancel);
    done.onCancel = () async {
      cancelled = true;
      generation++;
      _syncCancels.remove(cancel);
      await inner?.cancel();
    };
    _trackReceive(listen());
    return subscription;
  }

  /// Returns false if the message was deferred.
  Future<bool> _handle(
    String chatId,
    String msgId,
    Map<String, dynamic> data,
  ) async {
    try {
      await _lock.run(() async {
        if (!_closed) await _process(chatId, msgId, data);
      });
      if (_closed) return false;
      _deferred.remove('$chatId/$msgId');
      _unfinished.remove('$chatId/$msgId');
      return true;
    } on IdentityChangedException catch (e) {
      if (_closed) return false;
      _setAlert(e);
      _deferred['$chatId/$msgId'] = (chatId: chatId, msgId: msgId, data: data);
      return false;
    } catch (_) {
      if (_closed) return false;
      // Storage or network trouble (or a peer flooding invalid messages): keep
      // the message and try again shortly.
      _deferred['$chatId/$msgId'] = (chatId: chatId, msgId: msgId, data: data);
      _retryTimer ??= Timer(const Duration(seconds: 65), () {
        _retryTimer = null;
        retryDeferred();
      });
      return false;
    }
  }

  /// Reprocesses deferred messages (call after the user accepts an identity
  /// change, or when storage/network recovers).
  Future<void> retryDeferred() async {
    if (_closed) return;
    final items = _deferred.values.toList();
    _identityAlerts.clear();
    _alertCtrl.add(identityAlerts);
    for (final m in items) {
      await _handle(m.chatId, m.msgId, m.data);
    }
  }

  DateTime _ts(DocumentSnapshot<Map<String, dynamic>> d) =>
      (d.data()?['ts'] as Timestamp?)?.toDate() ?? DateTime.now();

  // ---- receive journal ------------------------------------------------------
  // After a message authenticates, its effects (history entry, advanced session,
  // spent one-time prekey) must all happen even if the app dies half way. The result
  // is first written as ONE journal record; applying it is idempotent and is
  // replayed before any other message is processed.

  String get _journalIndexKey => 'journals:${device.keys.deviceId}';
  String _journalKey(String chatId, String msgId) =>
      'journal:${device.keys.deviceId}:$chatId:$msgId';

  Future<List<String>> _journalIndex() async {
    final raw = await _secrets.read(_journalIndexKey);
    return raw == null ? [] : (jsonDecode(raw) as List).cast<String>();
  }

  Future<void> _writeJournal(Map<String, dynamic> j) async {
    final key = _journalKey(j['chatId'] as String, j['msgId'] as String);
    await _secrets.write(key, jsonEncode(j));
    final idx = await _journalIndex();
    if (!idx.contains(key)) {
      await _secrets.write(_journalIndexKey, jsonEncode([...idx, key]));
    }
  }

  Future<void> _applyJournal(Map<String, dynamic> j) async {
    final chatId = j['chatId'] as String, msgId = j['msgId'] as String;
    if (!await _messages.has(chatId, msgId)) {
      await _messages.add(
        LocalMessage(
          id: msgId,
          chatId: chatId,
          senderUid: j['senderUid'] as String,
          senderDevice: j['senderDevice'] as String,
          outgoing: false,
          sentAt: DateTime.fromMillisecondsSinceEpoch(j['sentAt'] as int),
          body: j['body'] as String,
          status: MessageStatus.values.byName(j['status'] as String),
        ),
      );
    }
    await _secrets.write(
      _sess.sessKey(j['senderUid'] as String, j['senderDevice'] as String),
      j['sessions'] as String,
    );
    final opk = j['opk'];
    if (opk is String) {
      await _prekeys.consumeOneTime(uid, device.keys.deviceId, opk);
    }
    final key = _journalKey(chatId, msgId);
    await _secrets.delete(key);
    final idx = await _journalIndex();
    await _secrets.write(
      _journalIndexKey,
      jsonEncode(idx.where((k) => k != key).toList()),
    );
  }

  /// Completes any message whose effects were only partly applied (call under the lock).
  Future<void> _recoverJournals() async {
    for (final key in await _journalIndex()) {
      final raw = await _secrets.read(key);
      if (raw == null) {
        final idx = await _journalIndex();
        await _secrets.write(
          _journalIndexKey,
          jsonEncode(idx.where((k) => k != key).toList()),
        );
        continue;
      }
      await _applyJournal(jsonDecode(raw) as Map<String, dynamic>);
    }
  }

  /// Decrypts one message and persists the result. Order matters: the
  /// plaintext is written to history BEFORE the advanced session is saved, so a
  /// crash in between costs nothing (the retry decrypts again, and the history
  /// check prevents a duplicate).
  Future<void> _process(
    String chatId,
    String msgId,
    Map<String, dynamic> data,
  ) async {
    await _recoverJournals(); // finish anything a crash left half applied, in order
    if (data['senderUid'] == uid &&
        data['senderDevice'] == device.keys.deviceId) {
      // Our own send, seen on the server: it WAS published, so a pending "not confirmed" warning
      // for it resolves by itself.
      await _confirmOwnSend(chatId, msgId);
      return;
    }
    if (await _messages.has(chatId, msgId)) return;
    final su = data['senderUid'];
    final sd = data['senderDevice'];
    final sentAt = data['ts'] is Timestamp
        ? (data['ts'] as Timestamp).toDate()
        : DateTime.now();

    Future<void> store(String body, MessageStatus status) => _messages.add(
      LocalMessage(
        id: msgId,
        chatId: chatId,
        senderUid: su is String ? su : '',
        senderDevice: sd is String ? sd : '',
        outgoing: false,
        sentAt: sentAt,
        body: body,
        status: status,
      ),
    );

    if (su is! String || sd is! String) {
      await store('Malformed message.', MessageStatus.undecryptable);
      return;
    }
    if (su == uid && sd == device.keys.deviceId) {
      return; // our own send
    }
    if (_safety?.isBlocked(su) ?? false) {
      return; // blocked: drop anything still in flight
    }

    final envs = data['envelopes'];
    final raw = envs is Map ? envs[device.keys.deviceId] : null;
    if (raw == null) {
      await store(
        'Sent before this device was added.',
        MessageStatus.undecryptable,
      );
      return;
    }
    final Envelope env;
    try {
      env = Envelope.fromJson(Map<String, dynamic>.from(raw as Map));
    } catch (e) {
      await store(
        e is FormatException && e.message.contains('protocol version')
            ? 'Sent with an incompatible app version.'
            : 'Malformed message.',
        MessageStatus.undecryptable,
      );
      return;
    }

    final sessions = await _sess.loadSessions(su, sd);
    Session? session;
    String? acceptedWith; // one-time prekey consumed by a new session
    for (final s in sessions) {
      if (s.sessionId == env.sid) session = s;
    }
    if (session == null) {
      final hs = env.handshake;
      if (hs == null) {
        await store('Missing session.', MessageStatus.undecryptable);
        return;
      }
      // May throw IdentityChangedException / network errors: deliberately
      // propagated so the message is retried rather than discarded.
      final remote = await _keys.fetchDevice(su, sd);
      if (remote == null) {
        await store('Unknown sender device.', MessageStatus.undecryptable);
        return;
      }
      final pre = await _prekeys.resolve(uid, device.keys.deviceId, hs);
      if (pre == null) {
        _repairPrekeys(); // our published prekeys may be out of step with what we hold
        await store(
          'Encryption key no longer available.',
          MessageStatus.undecryptable,
        );
        return;
      }
      try {
        session = await Session.accept(
          local: device.keys,
          localBundle: device.bundle,
          remote: remote,
          handshake: hs,
          signedPreKey: pre.signed,
          oneTimePreKey: pre.oneTime,
        );
      } catch (_) {
        await store('Invalid handshake.', MessageStatus.undecryptable);
        return;
      }
      acceptedWith = hs.opkId;
      if (session.sessionId != env.sid) {
        await store('Invalid handshake.', MessageStatus.undecryptable);
        return;
      }
      sessions.add(session);
    }

    final Uint8List plain;
    try {
      plain = await session.decrypt(env, chatId: chatId);
    } on SessionRateLimited {
      rethrow; // not the message's fault: try again later
    } on SessionException catch (e) {
      await store(
        'Could not decrypt (${e.message}).',
        MessageStatus.undecryptable,
      );
      return;
    } catch (_) {
      await store('Could not decrypt.', MessageStatus.undecryptable);
      return;
    }

    // The message authenticated, so its key is spent whatever the payload holds.
    var body = 'Malformed message.';
    var status = MessageStatus.undecryptable;
    try {
      final payload = jsonDecode(utf8.decode(plain));
      if (payload is Map &&
          payload['type'] == 'text' &&
          payload['body'] is String) {
        body = payload['body'] as String;
        status = MessageStatus.ok;
      } else {
        body = '[unsupported message]';
        status = MessageStatus.ok;
      }
    } catch (_) {}
    // Everything below is one recoverable unit: record the outcome in the journal, then
    // apply it. A crash or storage failure after this point is completed on the next run
    // instead of leaving the history written but the ratchet (or prekey erasure) undone.
    final journal = <String, dynamic>{
      'chatId': chatId,
      'msgId': msgId,
      'senderUid': su,
      'senderDevice': sd,
      'sentAt': sentAt.millisecondsSinceEpoch,
      'body': body,
      'status': status.name,
      'sessions': jsonEncode([for (final x in sessions) x.toJson()]),
      'opk': acceptedWith,
    };
    await _writeJournal(journal);
    await _applyJournal(journal);
  }
}
