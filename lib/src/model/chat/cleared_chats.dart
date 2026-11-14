import 'dart:async';
import 'dart:convert';

import 'package:fireplace/src/db/secret_store.dart';

/// The conversations this account deleted on this phone (issue 123).
///
/// Deleting one erases its messages here and takes it off the chat list. The
/// server copy and the other person's copy stay, so the chat still exists:
/// the list leaves it out while it has nothing to show, and shows it again
/// when a new message arrives or is sent. This remembers which chats to
/// leave out; it is kept on this device only.
class ClearedChats {
  ClearedChats(this._secrets, this.uid);
  final SecretStore _secrets;
  final String uid;
  var _chats = <String>{};
  final _changes = StreamController<void>.broadcast();

  static String keyName(String uid) => 'clearedchats:$uid';

  Future<void> load() async {
    try {
      final raw = await _secrets.read(keyName(uid));
      final json = raw == null ? null : jsonDecode(raw);
      _chats = {
        if (json is List)
          for (final id in json)
            if (id is String) id,
      };
    } catch (_) {
      // Unreadable: the chats show again, empty. Nothing is lost.
      _chats = {};
    }
  }

  Set<String> get chats => Set.unmodifiable(_chats);

  /// Fires when the set changes.
  Stream<void> get changes => _changes.stream;

  Future<void> add(String chatId) async {
    if (!_chats.add(chatId)) return;
    if (!_changes.isClosed) _changes.add(null);
    await _secrets.write(keyName(uid), jsonEncode(_chats.toList()));
  }

  Future<void> close() => _changes.close();
}
