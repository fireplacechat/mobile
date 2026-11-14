import 'dart:async';
import 'dart:convert';

import 'package:fireplace/src/db/secret_store.dart';

/// The colour each person this account chats with has chosen for themselves
/// (decision 0052). It arrives inside their 1:1 messages, encrypted like the
/// text, and is kept on this device only.
///
/// A person who has not sent a message since choosing shows in the default
/// colour until they do.
class PeerColors {
  PeerColors(this._secrets, this.uid);
  final SecretStore _secrets;
  final String uid;
  final _colors = <String, String>{};
  final _changes = StreamController<String>.broadcast();

  static String keyName(String uid) => 'peercolors:$uid';
  static final _name = RegExp(r'^[a-z]{1,24}$');

  /// A colour name as it travels: lower-case letters, nothing else.
  static bool valid(Object? color) => color is String && _name.hasMatch(color);

  Future<void> load() async {
    try {
      final raw = await _secrets.read(keyName(uid));
      if (raw == null) return;
      final json = jsonDecode(raw);
      if (json is! Map) return;
      for (final e in json.entries) {
        if (e.key is String && valid(e.value)) {
          _colors[e.key as String] = e.value as String;
        }
      }
    } catch (_) {
      // Unreadable colours must not prevent opening the app.
    }
  }

  /// The name of [peerUid]'s colour, or null when none has arrived.
  String? of(String peerUid) => _colors[peerUid];

  /// Fires with a person's id when their colour changes.
  Stream<String> get changes => _changes.stream;

  /// Records the colour a message from [peerUid] carried.
  Future<void> note(String peerUid, String color) async {
    if (peerUid == uid || !valid(color) || _colors[peerUid] == color) return;
    _colors[peerUid] = color;
    if (!_changes.isClosed) _changes.add(peerUid);
    try {
      await _secrets.write(keyName(uid), jsonEncode(_colors));
    } catch (_) {
      // It still shows until the app closes, and arrives again with the next
      // message.
    }
  }

  Future<void> close() => _changes.close();
}
