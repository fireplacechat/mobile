import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

typedef DeferredMessage = ({
  String chatId,
  String msgId,
  Map<String, dynamic> data,
});

/// Keeps retry work and the unfinished cursor boundary for this account.
class DeferredQueue {
  final Map<String, DeferredMessage> _deferred = {};
  final Map<String, ({String chatId, Timestamp? ts})> _unfinished = {};
  Timer? _retryTimer;

  List<DeferredMessage> get pending => _deferred.values.toList();
  bool get retryScheduled => _retryTimer != null;

  void defer(String chatId, String msgId, Map<String, dynamic> data) {
    _deferred['$chatId/$msgId'] = (chatId: chatId, msgId: msgId, data: data);
  }

  void registerUnfinished(String chatId, String msgId, Timestamp? ts) {
    _unfinished['$chatId/$msgId'] = (chatId: chatId, ts: ts);
  }

  void complete(String chatId, String msgId) {
    _deferred.remove('$chatId/$msgId');
    _unfinished.remove('$chatId/$msgId');
  }

  /// Never pass unfinished work; an unknown timestamp blocks this chat.
  Timestamp? clampCursor(String chatId, Timestamp? candidate) {
    if (candidate == null) return null;
    for (final u in _unfinished.values) {
      if (u.chatId != chatId) continue;
      final ts = u.ts;
      if (ts == null) return null;
      if (candidate != null && ts.compareTo(candidate) < 0) candidate = ts;
    }
    return candidate;
  }

  void scheduleRetry(void Function() retry) {
    _retryTimer ??= Timer(const Duration(seconds: 65), () {
      _retryTimer = null;
      retry();
    });
  }

  /// Cancel the timer before draining. Pending state is cleared after the lock.
  void close() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void clearDeferred() => _deferred.clear();
  void clearUnfinished() => _unfinished.clear();
}
