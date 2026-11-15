import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/model/chat/chat_exceptions.dart';

/// Where a saved message that has not been sent yet stands.
enum ResumeState {
  /// Being sent, or waiting a moment before the next try.
  sending,

  /// Not sent. It waits for the person to send it again or delete it.
  failed,
}

/// Finishes messages that were saved but whose send did not end: the app was
/// closed during the send, or the network dropped (decision 0059). Each is
/// looked up on the server, and sent again under its own id if it is not
/// there. The server never takes the same id twice, so this cannot deliver a
/// message twice.
///
/// The state holds only the messages still being worked on or given up on,
/// by message id. Account-scoped memory only.
class SendResume extends Notifier<Map<String, ResumeState>> {
  /// A message older than this is not sent by itself: the person wrote it
  /// too long ago to be surprised by it now. It can still be sent by hand.
  static const autoWithin = Duration(days: 1);

  /// The waits between tries while the outcome stays unknown.
  static List<Duration> pauses = const [
    Duration(seconds: 5),
    Duration(seconds: 20),
    Duration(seconds: 60),
  ];

  Object _generation = Object();
  final _running = <String>{};

  @override
  Map<String, ResumeState> build() {
    ref.watch(appSessionProvider.select((s) => s.value?.uid));
    _generation = Object();
    _running.clear();
    return const {};
  }

  /// A message of this account that is saved but not known to be sent.
  static bool unsent(LocalMessage m) =>
      m.outgoing &&
      m.status == MessageStatus.unconfirmed &&
      m.mutation == null &&
      !m.remotelyDeleted;

  /// Called with a conversation's messages whenever they change. Starts on
  /// each unsent message once.
  void noticed(Iterable<LocalMessage> messages, {DateTime? now}) {
    for (final m in messages) {
      if (!unsent(m) || state.containsKey(m.id) || _running.contains(m.id)) {
        continue;
      }
      if ((now ?? DateTime.now()).difference(m.sentAt) > autoWithin) {
        _set(m.id, ResumeState.failed);
      } else {
        _run(m.chatId, m.id);
      }
    }
  }

  /// The person asked for this message to be sent again.
  void tryAgain(String chatId, String messageId) {
    if (_running.contains(messageId)) return;
    _run(chatId, messageId);
  }

  void _set(String id, ResumeState? value) {
    if (state[id] == value) return;
    state = {
      for (final e in state.entries)
        if (e.key != id) e.key: e.value,
      id: ?value,
    };
  }

  Future<void> _run(String chatId, String id) async {
    _running.add(id);
    final generation = _generation;
    bool current() => ref.mounted && identical(generation, _generation);
    _set(id, ResumeState.sending);
    try {
      // Ends when it is sent, refused, or the tries run out.
      for (var attempt = 0; ; attempt++) {
        final chat = ref.read(appSessionProvider).value?.chat;
        if (chat == null) return;
        SendOutcome outcome;
        try {
          outcome = await chat.finishSend(chatId, id);
        } catch (_) {
          outcome = SendOutcome.publishUnknown;
        }
        if (!current()) return;
        if (outcome == SendOutcome.confirmed) {
          _set(id, null);
          return;
        }
        if (outcome == SendOutcome.notPublished || attempt >= pauses.length) {
          _set(id, ResumeState.failed);
          return;
        }
        await Future<void>.delayed(pauses[attempt]);
        if (!current()) return;
      }
    } finally {
      if (identical(generation, _generation)) _running.remove(id);
    }
  }
}

final sendResumeProvider =
    NotifierProvider<SendResume, Map<String, ResumeState>>(SendResume.new);
