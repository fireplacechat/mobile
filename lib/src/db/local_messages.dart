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

  /// The conversation as it is shown, oldest first, now and after each
  /// change. With [newest], at least that many of the newest messages: a
  /// long conversation is then not read whole (decision 0057). A store may
  /// give more than was asked for.
  Stream<List<LocalMessage>> watch(String chatId, {int? newest});

  /// The whole conversation as it is shown, once. For the few things that
  /// need all of it (search, a first-run baseline); it changes nothing for
  /// those watching.
  Future<List<LocalMessage>> all(String chatId);

  /// The readable messages in [chatIds] whose text [matches] accepts, newest
  /// first (ties by chat, then id), at most [limit]. Not edits, reactions or
  /// deletes, not lines about a group, and not what its author deleted.
  /// [matches] may run on another isolate, so it must not capture anything
  /// that cannot be sent there.
  Future<List<LocalMessage>> search(
    Set<String> chatIds,
    bool Function(String body) matches, {
    int limit = 100,
  });

  /// Gives those watching [chatId] at least [more] older messages as well,
  /// when there are any.
  Future<void> showOlder(String chatId, {int more = 200});

  /// Makes sure those watching [chatId] are given the message [messageId],
  /// however old, with a little of what came before it.
  Future<void> reveal(String chatId, String messageId);

  /// Records that the person has seen these messages (issue 180). Kept with
  /// each message, on this device only: nobody is told what was read.
  Future<void> markRead(String chatId, Iterable<String> messageIds);

  /// How many shown messages from other people have not been seen. Messages
  /// deleted by their author do not count. With [onlyOk], neither do lines
  /// that are not a readable message (a notice, an unreadable message).
  Future<int> unreadCount(String chatId, {bool onlyOk = false});

  /// Forget a whole conversation on this device.
  Future<void> deleteChat(String chatId);

  /// Erases the content of every message of a conversation on this device
  /// and keeps their hidden replay tombstones, as [remove] does for one. For
  /// a conversation that still exists on the server: a message seen again
  /// must not be decrypted a second time.
  Future<void> clearChat(String chatId);
}

/// [LocalMessageStore.search] for a store that reads whole conversations.
Future<List<LocalMessage>> searchWholeConversations(
  LocalMessageStore store,
  Set<String> chatIds,
  bool Function(String body) matches, {
  int limit = 100,
}) async {
  if (limit <= 0) return const [];
  final found = [
    for (final chatId in chatIds)
      for (final m in await store.all(chatId))
        if (m.status == MessageStatus.ok &&
            !m.remotelyDeleted &&
            matches(m.body))
          m,
  ];
  found.sort((a, b) {
    final byTime = b.sentAt.compareTo(a.sentAt);
    if (byTime != 0) return byTime;
    final byChat = a.chatId.compareTo(b.chatId);
    return byChat != 0 ? byChat : a.id.compareTo(b.id);
  });
  return found.take(limit).toList();
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
    _read.remove(chatId);
    _chats.remove(chatId);
    _ctrls[chatId]?.add(const []);
  }

  final Map<String, Set<String>> _read = {};
  @override
  Future<void> markRead(String chatId, Iterable<String> messageIds) async {
    (_read[chatId] ??= {}).addAll(messageIds);
  }

  @override
  Future<int> unreadCount(String chatId, {bool onlyOk = false}) async {
    final read = _read[chatId] ?? const <String>{};
    return _sorted(chatId)
        .where(
          (m) =>
              !m.outgoing &&
              !m.remotelyDeleted &&
              (!onlyOk || m.status == MessageStatus.ok) &&
              !read.contains(m.id),
        )
        .length;
  }

  // Everything is in memory already: a window would save nothing.
  @override
  Future<List<LocalMessage>> all(String chatId) async => _sorted(chatId);

  @override
  Future<List<LocalMessage>> search(
    Set<String> chatIds,
    bool Function(String body) matches, {
    int limit = 100,
  }) => searchWholeConversations(this, chatIds, matches, limit: limit);
  @override
  Future<void> showOlder(String chatId, {int more = 200}) async {}
  @override
  Future<void> reveal(String chatId, String messageId) async {}

  @override
  Future<void> clearChat(String chatId) async {
    final records = _chats[chatId];
    if (records == null) return;
    _chats[chatId] = {
      for (final id in records.keys) id: LocalMessage.tombstone(chatId, id),
    };
    _ctrls[chatId]?.add(const []);
  }

  @override
  Stream<List<LocalMessage>> watch(String chatId, {int? newest}) {
    final c = _ctrls[chatId] ??=
        StreamController<List<LocalMessage>>.broadcast();
    return Stream.multi((s) {
      s.add(_sorted(chatId));
      final sub = c.stream.listen(s.add);
      s.onCancel = sub.cancel;
    });
  }
}
