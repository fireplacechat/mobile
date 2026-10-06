import 'dart:async';

import 'package:fireplace/src/model/keys/key_service.dart';

/// Account-scoped identity warnings, including the initial stream snapshot.
class IdentityAlerts {
  final Map<String, List<int>> _identityAlerts = {};
  final _alertCtrl = StreamController<Map<String, List<int>>>.broadcast();

  Map<String, List<int>> get snapshot => Map.unmodifiable(_identityAlerts);
  Set<String> get peers => _identityAlerts.keys.toSet();

  void set(IdentityChangedException e) {
    _identityAlerts[e.peerUid] = e.newIdentityPub;
    _alertCtrl.add(snapshot);
  }

  void clear() {
    _identityAlerts.clear();
    _alertCtrl.add(snapshot);
  }

  Stream<Map<String, List<int>>> watch() => Stream.multi((sink) {
    // Attach first so an update triggered by the initial snapshot is retained.
    final sub = _alertCtrl.stream.listen(
      sink.add,
      onError: sink.addError,
      onDone: sink.close,
    );
    sink.onCancel = sub.cancel;
    sink.add(snapshot);
  });

  Future<void> close() => _alertCtrl.close();
}
