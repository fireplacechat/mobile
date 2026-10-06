import 'package:fireplace/src/model/chat/message_receiver.dart';
import 'package:fireplace/src/model/chat/message_sender.dart';
import 'package:fireplace/src/model/chat/chat_tuning.dart';
import 'package:fireplace/src/model/chat/deferred_queue.dart';
import 'package:fireplace/src/model/chat/work_tracker.dart';
import 'package:fireplace/src/model/chat/identity_alerts.dart';
import 'package:fireplace/src/model/chat/receive_journal.dart';
import 'package:fireplace/src/model/chat/send_recovery.dart';
import 'package:fireplace/src/model/chat/chat_directory.dart';
import 'package:fireplace/src/model/chat/session_store.dart';
// ignore_for_file: prefer_initializing_formals
import 'package:fireplace/src/model/chat/async_mutex.dart';
import 'package:fireplace/src/model/chat/chat_exceptions.dart';
import 'package:fireplace/src/model/chat/chat_summary.dart';

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:fireplace/src/crypto/session.dart';
import 'package:fireplace/src/model/keys/key_service.dart';
import 'package:fireplace/src/model/keys/prekey_service.dart';
import 'package:fireplace/src/model/safety/safety_service.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/db/secret_store.dart';

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
  late final _recovery = SendRecovery(
    _db,
    _messages,
    uid,
    device,
    sendText: sendText,
    peerOf: peerOf,
  );
  late final _journal = ReceiveJournal(
    _secrets,
    _messages,
    _prekeys,
    _sess,
    uid,
    device,
  );
  late final _sender = MessageSender(
    db: _db,
    keys: _keys,
    prekeys: _prekeys,
    secrets: _secrets,
    messages: _messages,
    safety: _safety,
    commitBatch: _commitBatch,
    uid: uid,
    device: device,
    lock: _lock,
    sess: _sess,
    journal: _journal,
    alerts: _alerts,
    peerOf: peerOf,
    messageRetention: messageRetention,
  );

  late final _receiver = MessageReceiver(
    db: _db,
    keys: _keys,
    prekeys: _prekeys,
    secrets: _secrets,
    messages: _messages,
    safety: _safety,
    uid: uid,
    device: device,
    lock: _lock,
    work: _work,
    queue: _queue,
    alerts: _alerts,
    sess: _sess,
    journal: _journal,
    recovery: _recovery,
  );

  final AsyncMutex _lock = AsyncMutex(); // serializes all session-state changes

  final _work = WorkTracker();

  /// Stop scheduling receives and drain work before local session storage closes.
  Future<void> close() => _work.close(() async {
    _work.markClosed();
    _queue.close();
    await _work.cancelAndDrain();
    await _lock.run(() async {});
    _queue.clearDeferred();
    _queue.clearUnfinished();
    unawaited(_alerts.close());
  });

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

  Future<void> sendText(String chatId, String text) =>
      _sender.sendText(chatId, text);

  Future<SendOutcome> checkSendStatus(String chatId, String messageId) =>
      _recovery.checkSendStatus(chatId, messageId);

  Future<void> saveSentLocally({
    required String chatId,
    required String messageId,
    required String body,
    required DateTime sentAt,
  }) => _recovery.saveSentLocally(
    chatId: chatId,
    messageId: messageId,
    body: body,
    sentAt: sentAt,
  );

  Future<void> resendUnconfirmed({
    required String chatId,
    required String messageId,
    required String body,
  }) => _recovery.resendUnconfirmed(
    chatId: chatId,
    messageId: messageId,
    body: body,
  );

  // ----------------------------------------------------------------- receive

  static const requestLimit = ChatTuning.requestLimit;

  static Duration get staleSessionAfter => ChatTuning.staleSessionAfter;
  static set staleSessionAfter(Duration value) {
    ChatTuning.staleSessionAfter = value;
  }

  static Session? pickSession(List<Session> sessions) =>
      SessionStore.pickSession(sessions);

  static Duration get sendGap => ChatTuning.sendGap;
  static set sendGap(Duration value) {
    ChatTuning.sendGap = value;
  }

  /// Messages that could not be processed yet (identity change awaiting the
  /// user, or a transient storage/network error). See [retryDeferred].
  final _queue = DeferredQueue();
  final _alerts = IdentityAlerts();

  /// Contacts whose changed identity is blocking messages, with the NEW identity key.
  Map<String, List<int>> get identityAlerts => _alerts.snapshot;
  Set<String> get identityAlertPeers => _alerts.peers;

  Stream<Map<String, List<int>>> watchIdentityAlerts() => _alerts.watch();

  @visibleForTesting
  Map<String, int> get syncPagesOpened => _receiver.syncPagesOpened;
  @visibleForTesting
  void Function(String chatId, List<String> ids)? get syncObserver =>
      _receiver.syncObserver;
  @visibleForTesting
  set syncObserver(void Function(String chatId, List<String> ids)? observer) {
    _receiver.syncObserver = observer;
  }

  StreamSubscription<void> startSync(String chatId, {int limit = 50}) =>
      _receiver.startSync(chatId, limit: limit);
  Future<void> retryDeferred() => _receiver.retryDeferred();
}
