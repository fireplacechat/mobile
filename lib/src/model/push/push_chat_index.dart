import 'dart:convert';

import 'package:fireplace/src/db/secret_store.dart';
import 'package:fireplace/src/model/notifications/notification_preview.dart';

/// The chats this device receives, kept by the app for the background push
/// handler (decision 0030). A push names its chat only by the opaque
/// conversation key; the handler hashes these ids the same way to find it.
/// Requests, blocked and hidden chats are not in it, so a push for them is
/// shown as "New Message" and nothing is decrypted.
class PushChatIndex {
  PushChatIndex(this._store, String uid) : _key = 'pushchats:$uid';

  final SecretStore _store;
  final String _key;
  Set<String>? _saved;

  /// Remembers [chatIds]. Writes only when the set changed.
  Future<void> save(Set<String> chatIds) async {
    final sorted = chatIds.toList()..sort();
    if (_saved != null && _saved!.length == sorted.length) {
      if (_saved!.containsAll(sorted)) return;
    }
    await _store.write(_key, jsonEncode(sorted));
    _saved = sorted.toSet();
  }

  /// The chat whose conversation key is [key], or null.
  Future<String?> chatFor(String key) async {
    final raw = await _store.read(_key);
    if (raw == null) return null;
    final List<dynamic> ids;
    try {
      ids = jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      return null;
    }
    for (final id in ids.whereType<String>()) {
      if (await conversationKey(id) == key) return id;
    }
    return null;
  }
}
