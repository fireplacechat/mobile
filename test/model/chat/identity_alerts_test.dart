import 'dart:async';

import 'package:fireplace/src/model/chat/identity_alerts.dart';
import 'package:fireplace/src/model/keys/key_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an alert set during the first snapshot is not lost', () async {
    final alerts = IdentityAlerts();
    final received = Completer<Map<String, List<int>>>();
    final sub = alerts.watch().listen((value) {
      if (value.isEmpty) {
        alerts.set(IdentityChangedException('bob', [1, 2]));
      } else if (!received.isCompleted) {
        received.complete(value);
      }
    });
    try {
      expect(await received.future.timeout(const Duration(seconds: 2)), {
        'bob': [1, 2],
      });
    } finally {
      await sub.cancel();
      await alerts.close();
    }
  });

  test('clear emits even when the snapshot was already empty', () async {
    final alerts = IdentityAlerts();
    final snapshots = <Map<String, List<int>>>[];
    final cleared = Completer<void>();
    final sub = alerts.watch().listen((value) {
      snapshots.add(value);
      if (snapshots.length == 3) cleared.complete();
    });
    await Future<void>.delayed(Duration.zero);
    alerts.set(IdentityChangedException('bob', [3]));
    alerts.clear();
    await cleared.future;
    expect(snapshots, [
      {},
      {
        'bob': [3],
      },
      {},
    ]);
    final next = sub.asFuture<void>();
    alerts.clear();
    await alerts.close();
    await next;
    expect(snapshots, [
      {},
      {
        'bob': [3],
      },
      {},
      {},
    ]);
  });

  test('close ends every subscriber stream', () async {
    final alerts = IdentityAlerts();
    final doneA = Completer<void>();
    final doneB = Completer<void>();
    alerts.watch().listen((_) {}, onDone: doneA.complete);
    alerts.watch().listen((_) {}, onDone: doneB.complete);
    await Future<void>.delayed(Duration.zero);
    await alerts.close();
    await Future.wait([doneA.future, doneB.future]);
  });

  test('snapshot maps and peer sets cannot mutate holder state', () async {
    final alerts = IdentityAlerts();
    alerts.set(IdentityChangedException('bob', [4]));
    final snapshot = alerts.snapshot;
    final peers = alerts.peers;
    expect(() => snapshot.clear(), throwsUnsupportedError);
    peers.clear();
    alerts.clear();
    expect(snapshot.keys, ['bob']);
    expect(alerts.peers, isEmpty);
    await alerts.close();
  });
}
