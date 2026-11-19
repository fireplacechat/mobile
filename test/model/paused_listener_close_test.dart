// A paused listener must not hold a session's close (issue 119). Riverpod
// pauses a provider that is out of view; the Delete account page covers the
// chat list, and deleting an account closes the session first. Closing a
// broadcast stream waits for every listener to take the done event, so
// awaiting it hung the deletion for good.
import 'dart:async';
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/model/chat/peer_colors.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_group_server.dart';
import '../support/group_phones.dart';

void main() {
  const limit = Duration(seconds: 5);
  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test('the group service closes with a paused invitations listener', () async {
    final root = await Directory.systemTemp.createTemp('paused_close');
    final db = FakeFirebaseFirestore();
    final server = FakeGroupServer(db);
    final alice = await Phone.create(db, 'alice', root);
    server.watchAccount('alice');
    // Listening first, as a screen does; paused once the stream is live.
    final subs = [
      alice.service.watchInvitations().listen((_) {}),
      alice.service.watchGroups().listen((_) {}),
    ];
    await settle();
    for (final sub in subs) {
      sub.pause();
    }
    await alice.service.close().timeout(limit);
    for (final sub in subs) {
      await sub.cancel();
    }
    await server.close();
    await root.delete(recursive: true);
  });

  test('the safety service closes with a paused blocked listener', () async {
    final safety = SafetyService(
      FakeFirebaseFirestore(),
      MemorySecretStore(),
      'alice',
    );
    await safety.start();
    final sub = safety.watchBlocked().listen((_) {});
    await settle();
    sub.pause();
    await safety.dispose().timeout(limit);
    await sub.cancel();
  });

  test('peer colours close with a paused listener', () async {
    final colors = PeerColors(MemorySecretStore(), 'alice');
    await colors.load();
    final sub = colors.changes.listen((_) {})..pause();
    await colors.close().timeout(limit);
    await sub.cancel();
  });
}
