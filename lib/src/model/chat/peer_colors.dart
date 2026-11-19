import 'dart:async';
import 'dart:convert';

import 'package:fireplace/src/db/secret_store.dart';

/// The colour each person this account chats with has chosen for themselves.
/// It is read from their profile (decision 0053) and remembered here, on this
/// device, so it shows at once the next time the app opens.
///
/// A person whose profile names no colour shows in the default colour.
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

  /// Records the colour [peerUid]'s profile shows; none, or one that is not
  /// a plain name, forgets what was remembered.
  Future<void> note(String peerUid, String? color) async {
    final next = valid(color) ? color : null;
    if (peerUid == uid || _colors[peerUid] == next) return;
    next == null ? _colors.remove(peerUid) : _colors[peerUid] = next;
    if (!_changes.isClosed) _changes.add(peerUid);
    try {
      await _secrets.write(keyName(uid), jsonEncode(_colors));
    } catch (_) {
      // It still shows until the app closes, and is read again next time.
    }
  }

  /// Not waiting for listeners: a paused one would hold the session's close
  /// (issue 119).
  Future<void> close() async => unawaited(_changes.close());
}
