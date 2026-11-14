import 'package:fireplace/src/db/message_edit.dart';
import 'package:fireplace/src/db/message_quote.dart';

import 'dart:async';

import 'package:fireplace/src/db/message_mutation.dart';
import 'package:fireplace/src/db/message_projection.dart';

enum MessageStatus {
  ok,
  undecryptable,

  /// Our own message whose publish outcome is not known: it may or may not have reached the
  /// server. Shown with a warning; never treated as sent, and resolved only by evidence from the
  /// server (see ChatService.checkSendStatus) or by an explicit decision to send another copy.
  unconfirmed,

  /// A line this device wrote into a group's history from an authenticated
  /// change ("alice added bob_jones"). The body is a `GroupNotice` in JSON,
  /// never text a person typed.
  notice,
}

class LocalMessage {
  LocalMessage({
    required this.id,
    required this.chatId,
    required this.senderUid,
    required this.senderDevice,
    required this.outgoing,
    required this.sentAt,
    required this.body,
    this.status = MessageStatus.ok,
    this.locallyDeleted = false,
    this.remotelyDeleted = false,
    this.mutation,
    this.quote,
    this.originalBody,
    this.editClock = 0,
    Map<int, MessageEdit> edits = const {},
    Map<String, MessageReaction> reactions = const {},
    Map<String, int> reactionClocks = const {},
  }) : edits = Map.unmodifiable(edits),
       reactions = Map.unmodifiable(reactions),
       reactionClocks = Map.unmodifiable(reactionClocks);

  final String id;
  final String chatId;
  final String senderUid;
  final String senderDevice;
  final bool outgoing;
  final DateTime sentAt;
  final String body; // plaintext, or a short reason when undecryptable
  final MessageStatus status;
  final bool locallyDeleted;
  final bool remotelyDeleted;
  final MessageMutation? mutation;
  final MessageQuote? quote;
  final String? originalBody;
  final int editClock;
  final Map<int, MessageEdit> edits;
  final Map<String, MessageReaction> reactions;
  final Map<String, int> reactionClocks;
  bool get visible => !locallyDeleted && mutation == null;

  LocalMessage copyWith({
    String? body,
    MessageQuote? quote,
    String? originalBody,
    int? editClock,
    Map<int, MessageEdit>? edits,
    bool? outgoing,
    MessageStatus? status,
    bool? remotelyDeleted,
    Map<String, MessageReaction>? reactions,
    Map<String, int>? reactionClocks,
  }) => LocalMessage(
    id: id,
    chatId: chatId,
    senderUid: senderUid,
    senderDevice: senderDevice,
    outgoing: outgoing ?? this.outgoing,
    sentAt: sentAt,
    body: body ?? this.body,
    status: status ?? this.status,
    locallyDeleted: locallyDeleted,
    remotelyDeleted: remotelyDeleted ?? this.remotelyDeleted,
    mutation: mutation,
    quote: quote ?? this.quote,
    originalBody: originalBody ?? this.originalBody,
    editClock: editClock ?? this.editClock,
    edits: edits ?? this.edits,
    reactions: reactions ?? this.reactions,
    reactionClocks: reactionClocks ?? this.reactionClocks,
  );

  factory LocalMessage.tombstone(String chatId, String id) => LocalMessage(
    id: id,
    chatId: chatId,
    senderUid: '',
    senderDevice: '',
    outgoing: false,
    sentAt: DateTime.fromMillisecondsSinceEpoch(0),
    body: '',
    locallyDeleted: true,
  );

  /// Account-relative direction for presentation. Stored `outgoing` records
  /// device-level send/receive bookkeeping, including linked-device copies.
  LocalMessage forAccount(String uid) {
    final mine = senderUid == uid;
    if (outgoing == mine) return this;
    return copyWith(outgoing: mine);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'chatId': chatId,
    'senderUid': senderUid,
    'senderDevice': senderDevice,
    'outgoing': outgoing,
    'sentAt': sentAt.millisecondsSinceEpoch,
    'body': body,
    'status': status.name,
    if (locallyDeleted) 'locallyDeleted': true,
    if (remotelyDeleted) 'remotelyDeleted': true,
    if (mutation != null) 'mutation': mutation!.toJson(),
    if (quote != null) 'quote': quote!.toJson(),
    if (originalBody != null) 'originalBody': originalBody,
    if (editClock != 0) 'editClock': editClock,
    if (edits.isNotEmpty)
      'edits': {
        for (final e in edits.entries) e.key.toString(): e.value.toJson(),
      },
    if (reactions.isNotEmpty)
      'reactions': {for (final e in reactions.entries) e.key: e.value.toJson()},
    if (reactionClocks.isNotEmpty) 'reactionClocks': reactionClocks,
  };

  factory LocalMessage.fromJson(Map<String, dynamic> j) => LocalMessage(
    id: j['id'],
    chatId: j['chatId'],
    senderUid: j['senderUid'],
    senderDevice: j['senderDevice'],
    outgoing: j['outgoing'],
    sentAt: DateTime.fromMillisecondsSinceEpoch(j['sentAt']),
    body: j['body'],
    originalBody: j['originalBody'],
    editClock: j['editClock'] ?? 0,
    edits: {
      for (final e in (j['edits'] as Map? ?? {}).entries)
        int.parse(e.key): MessageEdit.fromJson(
          Map<String, dynamic>.from(e.value),
        ),
    },
    quote: j['quote'] == null
        ? null
        : MessageQuote.fromJson(Map<String, dynamic>.from(j['quote'])),
    status: MessageStatus.values.byName(j['status']),
    locallyDeleted: j['locallyDeleted'] == true,
    remotelyDeleted: j['remotelyDeleted'] == true,
    reactionClocks: Map<String, int>.from(j['reactionClocks'] as Map? ?? {}),
    mutation: j['mutation'] == null
        ? null
        : MessageMutation.fromJson(Map<String, dynamic>.from(j['mutation'])),
    reactions: {
      for (final e in (j['reactions'] as Map? ?? {}).entries)
        e.key as String: MessageReaction.fromJson(
          Map<String, dynamic>.from(e.value),
        ),
    },
  );
}

/// On-device plaintext history. Ratchet keys are deleted after use, so a message
/// can be decrypted only once; the result MUST be persisted here.
/// The disk-backed, encrypted implementation arrives with the UI (Phase 4).
abstract class LocalMessageStore {
  /// Includes hidden deletion tombstones, which suppress ciphertext replay.
  Future<bool> has(String chatId, String messageId);
  Future<void> add(LocalMessage m);

  /// One stored message, or null.
  Future<LocalMessage?> get(String chatId, String messageId);

  /// Erases content and retains a hidden replay tombstone on this device.
  Future<void> remove(String chatId, String messageId);
  Stream<List<LocalMessage>> watch(String chatId);

  /// Forget a whole conversation on this device.
  Future<void> deleteChat(String chatId);
}

class MemoryMessageStore implements LocalMessageStore {
  final Map<String, Map<String, LocalMessage>> _chats = {};
  final Map<String, StreamController<List<LocalMessage>>> _ctrls = {};

  List<LocalMessage> _sorted(String chatId) =>
      (_chats[chatId]?.values.where((m) => m.visible).toList() ??
            <LocalMessage>[])
        ..sort((a, b) => a.sentAt.compareTo(b.sentAt));

  @override
  Future<bool> has(String chatId, String messageId) async =>
      _chats[chatId]?.containsKey(messageId) ?? false;

  @override
  Future<void> add(LocalMessage m) async {
    if (_chats[m.chatId]?[m.id]?.locallyDeleted == true) return;
    _chats[m.chatId] = projectMessageRecords({...?_chats[m.chatId], m.id: m});
    _ctrls[m.chatId]?.add(_sorted(m.chatId));
  }

  @override
  Future<LocalMessage?> get(String chatId, String messageId) async {
    final m = _chats[chatId]?[messageId];
    return m?.locallyDeleted == true ? null : m;
  }

  @override
  Future<void> remove(String chatId, String messageId) async {
    (_chats[chatId] ??= {})[messageId] = LocalMessage.tombstone(
      chatId,
      messageId,
    );
    _chats[chatId] = projectMessageRecords(_chats[chatId]!);
    _ctrls[chatId]?.add(_sorted(chatId));
  }

  @override
  Future<void> deleteChat(String chatId) async {
    _chats.remove(chatId);
    _ctrls[chatId]?.add(const []);
  }

  @override
  Stream<List<LocalMessage>> watch(String chatId) {
    final c = _ctrls[chatId] ??=
        StreamController<List<LocalMessage>>.broadcast();
    return Stream.multi((s) {
      s.add(_sorted(chatId));
      final sub = c.stream.listen(s.add);
      s.onCancel = sub.cancel;
    });
  }
}
