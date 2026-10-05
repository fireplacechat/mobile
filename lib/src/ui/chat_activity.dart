import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/services/chat_service.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/ui/message_format.dart';

final chatRouteObserver = RouteObserver<ModalRoute<void>>();

class ChatVisibility extends Notifier<String?> {
  @override
  String? build() {
    ref.watch(appSessionProvider.select((s) => s.value?.uid));
    return null;
  }

  void show(String? id) {
    if (ref.mounted) state = id;
  }

  void clearIf(String id) {
    if (ref.mounted && state == id) state = null;
  }
}

final visibleChatProvider = NotifierProvider<ChatVisibility, String?>(
  ChatVisibility.new,
);

class ChatActivityState {
  const ChatActivityState({
    this.history = const {},
    this.unread = const {},
    this.muted = const {},
    this.previewText = true,
    this.preferencesAvailable = true,
    this.arrivals = const [],
    this.loading = true,
    this.failed = const {},
  });
  final Map<String, List<LocalMessage>> history;
  final Map<String, int> unread;
  final Set<String> muted, failed;
  final bool previewText, loading, preferencesAvailable;
  final List<LocalMessage> arrivals;
  int otherUnread(String chatId) => unread.entries
      .where((e) => e.key != chatId && !muted.contains(e.key))
      .fold(0, (a, b) => a + b.value);
}

/// Keeps subscriptions to local history while signed in. The initial snapshot
/// never emits a notification. Replacements/status repairs are not new arrivals.
class ChatActivity extends Notifier<ChatActivityState> {
  final _history = <String, List<LocalMessage>>{};
  final _known = <String, Set<String>>{};
  final _failed = <String>{};
  final _listeners = <String, void Function()>{};
  final _listenerTokens = <String, Object>{};
  List<LocalMessage> _arrivals = [];
  List<ChatSummary> _chats = [];
  AppSession? _session;
  int _generation = 0;

  @override
  ChatActivityState build() {
    _session = ref.watch(appSessionProvider).value;
    final generation = ++_generation;
    _history.clear();
    _known.clear();
    _failed.clear();
    _listeners.clear();
    _listenerTokens.clear();
    _arrivals = [];
    _chats = [];
    final session = _session;
    ref.onDispose(() {
      _generation++;
      for (final close in _listeners.values) {
        close();
      }
      _listeners.clear();
      _listenerTokens.clear();
    });
    if (session == null) return const ChatActivityState(loading: false);
    final changes = session.chatPreferences.changes.listen((_) => _refresh());
    ref.onDispose(() {
      unawaited(changes.cancel());
    });
    void later(void Function() f) => scheduleMicrotask(() {
      if (_generation == generation) f();
    });
    ref.listen(
      chatsProvider,
      (_, next) => later(() {
        if (next.value != null) {
          _reconcile(next.value!);
        }
      }),
      fireImmediately: true,
    );
    ref.listen(blockedUidsProvider, (_, _) => later(_refresh));
    ref.listen(hiddenChatsProvider, (_, _) => later(_refresh));
    ref.listen(identityAlertsProvider, (_, _) => later(_refresh));
    return const ChatActivityState();
  }

  bool eligible(ChatSummary c) {
    final s = _session;
    final account = ref.read(appSessionProvider);
    final blocked = ref.read(blockedUidsProvider);
    final hidden = ref.read(hiddenChatsProvider);
    final alerts = ref.read(identityAlertsProvider);
    return s != null &&
        !account.isLoading &&
        !account.hasError &&
        identical(account.value, s) &&
        !blocked.isLoading &&
        !hidden.isLoading &&
        !alerts.isLoading &&
        !c.isIncomingRequest(s.uid) &&
        blocked.hasValue &&
        hidden.hasValue &&
        alerts.hasValue &&
        !blocked.hasError &&
        !hidden.hasError &&
        !alerts.hasError &&
        !blocked.value!.contains(c.peerUid) &&
        !hidden.value!.contains(c.chatId) &&
        !alerts.value!.containsKey(c.peerUid);
  }

  void _reconcile(List<ChatSummary> list) {
    _chats = list;
    final wanted = {
      for (final c in list)
        if (!c.isIncomingRequest(_session!.uid)) c.chatId,
    };
    for (final id in _listeners.keys.toList()) {
      if (!wanted.contains(id)) {
        _listeners.remove(id)!();
        _listenerTokens.remove(id);
        _history.remove(id);
        _known.remove(id);
        _failed.remove(id);
      }
    }
    for (final id in wanted) {
      if (_listeners.containsKey(id)) continue;
      final generation = _generation;
      final token = Object();
      _listenerTokens[id] = token;
      final subscription = ref.listen(messagesProvider(id), (_, next) {
        scheduleMicrotask(() {
          if (_generation != generation || _listenerTokens[id] != token) return;
          if (next.hasError) {
            _failed.add(id);
            _history.remove(id);
          }
          if (next.value != null && !next.hasError) {
            final messages = next.value!;
            final known = _known[id];
            if (known != null) {
              final chat = _chats.where((c) => c.chatId == id).firstOrNull;
              if (chat != null && eligible(chat)) {
                for (final m in messages) {
                  if (!m.outgoing &&
                      m.status == MessageStatus.ok &&
                      !known.contains(m.id)) {
                    _arrivals.add(m);
                  }
                }
                // A bounded queue; never keep message bodies after dismissal.
                if (_arrivals.length > 5) {
                  _arrivals = _arrivals.sublist(_arrivals.length - 5);
                }
              }
            }
            (_known[id] ??= {}).addAll(messages.map((m) => m.id));
            _history[id] = messages;
            _failed.remove(id);
            final prefs = _session!.chatPreferences;
            if (prefs.available && prefs.needsBaseline(id)) {
              unawaited(
                prefs
                    .seedExisting(
                      id,
                      messages.where((m) => !m.outgoing).map((m) => m.id),
                    )
                    .catchError((Object _) {}),
              );
            }
          }
          _refresh();
        });
      }, fireImmediately: true);
      _listeners[id] = subscription.close;
    }
    _refresh();
  }

  void _refresh() {
    final prefs = _session?.chatPreferences;
    final allowed = {
      for (final c in _chats)
        if (eligible(c)) c.chatId,
    };
    _arrivals = (prefs?.available ?? true)
        ? _arrivals
              .where(
                (m) =>
                    allowed.contains(m.chatId) &&
                    !(prefs?.needsBaseline(m.chatId) ?? false),
              )
              .toList()
        : [];
    state = ChatActivityState(
      history: Map.unmodifiable({
        for (final e in _history.entries)
          if (allowed.contains(e.key)) e.key: e.value,
      }),
      preferencesAvailable: prefs?.available ?? true,
      unread: {
        for (final e in _history.entries)
          if (allowed.contains(e.key) &&
              (prefs?.available ?? true) &&
              !(prefs?.needsBaseline(e.key) ?? false))
            e.key: e.value
                .where(
                  (m) =>
                      !m.outgoing &&
                      !(prefs?.seen[e.key]?.contains(m.id) ?? false),
                )
                .length,
      },
      muted: Set.unmodifiable(prefs?.muted ?? {}),
      previewText: prefs?.previewText ?? true,
      arrivals: List.unmodifiable(
        _arrivals.where((m) => allowed.contains(m.chatId)),
      ),
      loading: _chats.any(
        (c) =>
            allowed.contains(c.chatId) &&
            !_history.containsKey(c.chatId) &&
            !_failed.contains(c.chatId),
      ),
      failed: Set.unmodifiable(_failed.where(allowed.contains)),
    );
  }

  void dismissArrivals() {
    _arrivals = [];
    _refresh();
  }

  Future<void> seen(String id, Iterable<LocalMessage> messages) async {
    await _session?.chatPreferences.markSeen(
      id,
      messages.where((m) => !m.outgoing).map((m) => m.id),
    );
  }

  Future<void> mute(String id, bool value) async {
    await _session?.chatPreferences.mute(id, value);
  }

  Future<void> previews(bool value) async {
    await _session?.chatPreferences.previews(value);
  }

  Future<void> resetPreferences() async {
    final session = _session;
    if (session == null) return;
    final history = <String, Set<String>>{};
    for (final c in _chats) {
      final messages = await session.chat.watchMessages(c.chatId).first;
      history[c.chatId] = {
        for (final m in messages)
          if (!m.outgoing) m.id,
      };
    }
    if (!ref.mounted || !identical(session, _session)) return;
    await session.chatPreferences.reset(history: history);
  }
}

final chatActivityProvider = NotifierProvider<ChatActivity, ChatActivityState>(
  ChatActivity.new,
);

String unreadLabel(int count) => count > 99 ? '99+' : '$count';

class MessageSearchHit {
  MessageSearchHit(this.message, this.text, this.start, this.end);
  final LocalMessage message;
  final String text;
  final int start, end;
}

/// Literal, case-insensitive Unicode search. Accents are significant; emoji and
/// combining sequences remain intact. No regex from user input, no disk index.
List<MessageSearchHit> searchMessages(
  Map<String, List<LocalMessage>> history,
  String query, {
  int limit = 100,
}) {
  // Fold the query the same way as the text (per character) so final sigma and similar match.
  String fold(String s) => s.runes
      .map((r) => String.fromCharCode(r).toLowerCase())
      .join()
      .replaceAll('ς', 'σ');
  final needle = fold(query.trim());
  if (needle.isEmpty) return [];
  if (limit <= 0) return [];
  final results = <MessageSearchHit>[];
  int compare(MessageSearchHit a, MessageSearchHit b) {
    final byTime = b.message.sentAt.compareTo(a.message.sentAt);
    if (byTime != 0) return byTime;
    final byChat = a.message.chatId.compareTo(b.message.chatId);
    return byChat == 0 ? a.message.id.compareTo(b.message.id) : byChat;
  }

  for (final messages in history.values) {
    for (final m in messages) {
      if (m.status == MessageStatus.undecryptable) continue;
      final text = displayMessage(m.body).plain;
      // Lowercasing can change UTF-16 length (e.g. U+0130). Map offsets back.
      final folded = StringBuffer();
      final starts = <int>[], ends = <int>[];
      var offset = 0;
      for (final rune in text.runes) {
        final original = String.fromCharCode(rune),
            lower = original.toLowerCase();
        folded.write(lower == 'ς' ? 'σ' : lower);
        for (var i = 0; i < lower.length; i++) {
          starts.add(offset);
          ends.add(offset + original.length);
        }
        offset += original.length;
      }
      final start = folded.toString().indexOf(needle);
      if (start >= 0) {
        results.add(
          MessageSearchHit(
            m,
            text,
            starts[start],
            ends[start + needle.length - 1],
          ),
        );
        results.sort(compare);
        if (results.length > limit) results.removeLast();
      }
    }
  }
  return results;
}
