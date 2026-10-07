import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fireplace/src/crypto/session.dart';
import 'package:fireplace/src/model/keys/key_service.dart';
import 'package:fireplace/src/model/keys/prekey_service.dart';
import 'package:fireplace/src/model/safety/safety_service.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/db/secret_store.dart';
import 'package:fireplace/src/model/chat/async_mutex.dart';
import 'package:fireplace/src/model/chat/session_store.dart';
import 'package:fireplace/src/model/chat/receive_journal.dart';
import 'package:fireplace/src/model/chat/send_recovery.dart';
import 'package:fireplace/src/model/chat/identity_alerts.dart';
import 'package:fireplace/src/model/chat/work_tracker.dart';
import 'package:fireplace/src/model/chat/deferred_queue.dart';
import 'package:fireplace/src/model/chat/chat_tuning.dart';
import 'package:fireplace/src/model/chat/chat_exceptions.dart';

class MessageReceiver {
  MessageReceiver({
    required FirebaseFirestore db,
    required KeyService keys,
    required PreKeyService prekeys,
    required SecretStore secrets,
    required LocalMessageStore messages,
    SafetyService? safety,
    required String uid,
    required LocalDevice device,
    required AsyncMutex lock,
    required WorkTracker work,
    required DeferredQueue queue,
    required IdentityAlerts alerts,
    required SessionStore sess,
    required ReceiveJournal journal,
    required SendRecovery recovery,
    required String Function(String chatId) peerOf,
  }) : this._(
         db,
         keys,
         prekeys,
         secrets,
         messages,
         safety,
         uid,
         device,
         lock,
         work,
         queue,
         alerts,
         sess,
         journal,
         recovery,
         peerOf,
       );

  MessageReceiver._(
    this._db,
    this._keys,
    this._prekeys,
    this._secrets,
    this._messages,
    this._safety,
    this.uid,
    this.device,
    this._lock,
    this._work,
    this._queue,
    this._alerts,
    this._sess,
    this._journal,
    this._recovery,
    this._peerOf,
  );

  final FirebaseFirestore _db;
  final KeyService _keys;
  final PreKeyService _prekeys;
  final SecretStore _secrets;
  final LocalMessageStore _messages;
  final SafetyService? _safety;
  final String uid;
  final LocalDevice device;
  final AsyncMutex _lock;
  final WorkTracker _work;
  final DeferredQueue _queue;
  final IdentityAlerts _alerts;
  final SessionStore _sess;
  final ReceiveJournal _journal;
  final SendRecovery _recovery;
  final String Function(String chatId) _peerOf;

  /// Test hooks: how many query pages each chat's sync has opened, and which documents each
  /// snapshot delivered. Used to assert that paging makes progress and does not re-read.
  final Map<String, int> syncPagesOpened = {};
  void Function(String chatId, List<String> ids)? syncObserver;

  DateTime? _lastRepair;

  /// A peer used a prekey we cannot answer: drop orphaned published prekeys and
  /// refill the pool (at most once a minute, in the background).
  void _repairPrekeys() {
    if (_work.closed) return;
    final now = DateTime.now();
    if (_lastRepair != null &&
        now.difference(_lastRepair!) < const Duration(minutes: 1)) {
      return;
    }
    _lastRepair = now;
    _work.track(_prekeys.maintain(uid, device));
  }

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
    if (_work.closed) throw StateError('Chat service is closed.');
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? inner;
    var cancelled = false;
    var generation = 0;
    DocumentSnapshot<Map<String, dynamic>>? pageAfter;
    final done = StreamController<void>();
    final col = _db.collection('chats').doc(chatId).collection('messages');

    Future<void> listen() async {
      if (cancelled || _work.closed) return;
      final mine = ++generation;
      final cursor = await _cursor(chatId);
      if (cancelled || _work.closed || mine != generation) return;
      Query<Map<String, dynamic>> q;
      if (cursor == null) {
        q = col.orderBy('ts', descending: true).limit(limit);
      } else {
        q = col.where('ts', isGreaterThanOrEqualTo: cursor).orderBy('ts');
        // Continue after the last document already read (ties on `ts` are broken by document
        // id), never from the cursor again.
        if (pageAfter != null) q = q.startAfterDocument(pageAfter!);
        q = q.limit(ChatTuning.pageCap);
      }
      syncPagesOpened[chatId] = (syncPagesOpened[chatId] ?? 0) + 1;
      inner = q.snapshots().listen((snap) {
        _work.track(() async {
          if (cancelled || _work.closed || mine != generation) return;
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
            _queue.registerUnfinished(chatId, d.id, t is Timestamp ? t : null);
          }
          for (final d in added) {
            if (cancelled || _work.closed || mine != generation) return;
            final ok = await _handle(chatId, d.id, d.data()!);
            if (!ok) blocked = true;
            final ts = d.data()!['ts'];
            // Never advance past a message we still owe a retry.
            if (!blocked && ts is Timestamp) advanceTo = ts;
          }
          // Re-read from the oldest unfinished timestamp: stored messages are skipped.
          // An unfinished message without a timestamp blocks advancing this chat.
          advanceTo = _queue.clampCursor(chatId, advanceTo);
          if (advanceTo != null &&
              !cancelled &&
              !_work.closed &&
              mine == generation) {
            try {
              await _advanceCursor(chatId, advanceTo);
            } catch (_) {
              // Only an optimisation: without it the next run re-reads these messages, and
              // messages already stored are skipped. Must not escape the listener.
            }
          }
          if (cursor != null &&
              snap.docs.length >= ChatTuning.pageCap &&
              !cancelled &&
              !_work.closed &&
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
    _work.addCancel(cancel);
    done.onCancel = () async {
      cancelled = true;
      generation++;
      _work.removeCancel(cancel);
      await inner?.cancel();
    };
    _work.track(listen());
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
        if (!_work.closed) await _process(chatId, msgId, data);
      });
      if (_work.closed) return false;
      _queue.complete(chatId, msgId);
      return true;
    } on IdentityChangedException catch (e) {
      if (_work.closed) return false;
      _alerts.set(e);
      _queue.defer(chatId, msgId, data);
      return false;
    } catch (_) {
      if (_work.closed) return false;
      // Storage or network trouble (or a peer flooding invalid messages): keep
      // the message and try again shortly.
      _queue.defer(chatId, msgId, data);
      _queue.scheduleRetry(retryDeferred);
      return false;
    }
  }

  /// Reprocesses deferred messages (call after the user accepts an identity
  /// change, or when storage/network recovers).
  Future<void> retryDeferred() async {
    if (_work.closed) return;
    final items = _queue.pending;
    _alerts.clear();
    for (final m in items) {
      await _handle(m.chatId, m.msgId, m.data);
    }
  }

  DateTime _ts(DocumentSnapshot<Map<String, dynamic>> d) =>
      (d.data()?['ts'] as Timestamp?)?.toDate() ?? DateTime.now();

  /// Decrypts one message and persists the result. Order matters: the
  /// plaintext is written to history BEFORE the advanced session is saved, so a
  /// crash in between costs nothing (the retry decrypts again, and the history
  /// check prevents a duplicate).
  Future<void> _process(
    String chatId,
    String msgId,
    Map<String, dynamic> data,
  ) async {
    // Authorize before journal replay, pending-send confirmation or placeholders.
    // A sender must be this account or the peer encoded in a valid chat ID.
    final su = data['senderUid'];
    final sd = data['senderDevice'];
    final String peer;
    try {
      peer = _peerOf(chatId);
    } on ChatException {
      return;
    }
    if (su is! String || (su != uid && su != peer)) return;
    await _journal.recoverJournals(); // finish anything a crash left half applied, in order
    if (data['senderUid'] == uid &&
        data['senderDevice'] == device.keys.deviceId) {
      // Our own send, seen on the server: it WAS published, so a pending "not confirmed" warning
      // for it resolves by itself.
      await _recovery.confirmOwnSend(chatId, msgId);
      return;
    }
    if (await _messages.has(chatId, msgId)) return;
    final sentAt = data['ts'] is Timestamp
        ? (data['ts'] as Timestamp).toDate()
        : DateTime.now();

    Future<void> store(String body, MessageStatus status) => _messages.add(
      LocalMessage(
        id: msgId,
        chatId: chatId,
        senderUid: su,
        senderDevice: sd is String ? sd : '',
        outgoing: false,
        sentAt: sentAt,
        body: body,
        status: status,
      ),
    );

    if (sd is! String) {
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
    await _journal.writeJournal(journal);
    await _journal.applyJournal(journal);
  }
}
