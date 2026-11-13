import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';

import 'package:fireplace/src/db/secret_store.dart';

/// Serialises credential writes, so a late refresh cannot restore a signed-out
/// user's token. Values stay solely in the platform keychain, never in files.
class PreviewCredentialCache {
  PreviewCredentialCache(this._store);
  static const key = 'ios-preview-auth';
  final SecretStore _store;
  Future<void> _writes = Future.value();
  int _epoch = 0;
  bool _closed = false;

  Future<void> _write(Future<void> Function() action) {
    final next = _writes.then((_) => action(), onError: (Object _) => action());
    _writes = next;
    return next;
  }

  Future<void> clear() {
    _epoch++;
    return _write(() => _store.delete(key));
  }

  Future<void> update(Future<String?> Function() load) async {
    if (_closed) return;
    final epoch = ++_epoch;
    // Invalidate the old account before waiting for a new credential. Failure
    // leaves previews disabled instead of retaining another account's access.
    await _write(() => _store.delete(key));
    final value = await load();
    if (value == null || _closed || epoch != _epoch) return;
    await _write(() async {
      if (!_closed && epoch == _epoch) await _store.write(key, value);
    });
  }

  Future<void> close() async {
    _closed = true;
    _epoch++;
    await _writes;
  }
}

class IosPreviewCredentials {
  IosPreviewCredentials(this._auth, SecretStore store)
    : _cache = PreviewCredentialCache(store);
  final FirebaseAuth _auth;
  final PreviewCredentialCache _cache;
  StreamSubscription<User?>? _subscription;
  bool _suspended = false;

  void start() {
    _subscription = _auth.idTokenChanges().listen(
      (user) {
        if (user == null) {
          _suspended = false;
          unawaited(_cache.clear().catchError((Object _) {}));
        } else if (!_suspended) {
          unawaited(
            _cache
                .update(() async {
                  final token = await user.getIdTokenResult();
                  final refresh = user.refreshToken;
                  if (_auth.currentUser?.uid != user.uid ||
                      token.token == null ||
                      token.expirationTime == null ||
                      refresh == null ||
                      refresh.isEmpty) {
                    return null;
                  }
                  return jsonEncode({
                    'uid': user.uid,
                    'idToken': token.token,
                    'refreshToken': refresh,
                    'expiresAt': token.expirationTime!.millisecondsSinceEpoch,
                    'projectId': _auth.app.options.projectId,
                    'apiKey': _auth.app.options.apiKey,
                  });
                })
                .catchError((Object _) {}),
          );
        }
      },
      onError: (Object _) {
        unawaited(_cache.clear().catchError((Object _) {}));
      },
    );
  }

  Future<void> beforeLocalSignOut() async {
    _suspended = true;
    await _cache.clear();
  }

  Future<void> close() async {
    await _subscription?.cancel();
    await _cache.close(); // Keep a signed-in token for closed-app previews.
  }
}
