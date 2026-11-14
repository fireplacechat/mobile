// Stands in for the backend's group function (backend decision 0023) over a
// FakeFirebaseFirestore: it completes membership requests the way
// functions/lib/groups.js does, without the checks the tests do not exercise.
// The rules are tested in the backend repository.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

class FakeGroupServer {
  FakeGroupServer(this.db);
  final FakeFirebaseFirestore db;
  final _subs = <StreamSubscription<Object?>>[];
  final _watched = <String>{};
  final _done = <String>{};
  final processed = <String>[];

  String _slot(int e) => '$e'.padLeft(12, '0');

  void watchAccount(String uid) {
    _subs.add(
      db.collection('users/$uid/groupOps').snapshots().listen((s) {
        for (final d in s.docs) {
          unawaited(_handle(d.reference, d.data(), (op) => _account(uid, op)));
        }
      }),
    );
  }

  void _watchGroup(String gid) {
    if (!_watched.add(gid)) return;
    _subs.add(
      db.collection('groups/$gid/ops').snapshots().listen((s) {
        for (final d in s.docs) {
          unawaited(_handle(d.reference, d.data(), (op) => _group(gid, op)));
        }
      }),
    );
  }

  // One request at a time, as the backend's transactions serialise them.
  Future<void> _queue = Future<void>.value();

  Future<void> _handle(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> op,
    Future<void> Function(Map<String, dynamic>) run,
  ) {
    if (op['status'] != null || !_done.add(ref.path)) return Future.value();
    final next = _queue.then((_) => _handleNow(ref, op, run));
    _queue = next.catchError((Object _) {});
    return next;
  }

  Future<void> _handleNow(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> op,
    Future<void> Function(Map<String, dynamic>) run,
  ) async {
    try {
      await run(op);
      processed.add('${op['kind']}');
      await ref.update({
        'status': 'done',
        'commit': FieldValue.delete(),
        'welcome': FieldValue.delete(),
      });
    } on _Refused catch (e) {
      processed.add('${op['kind']}:refused');
      await ref.update({'status': 'refused', 'reason': e.reason});
    } catch (e, st) {
      // ignore: avoid_print
      print('fake server ${op['kind']} failed: $e $st');
      rethrow;
    }
  }

  Future<void> _account(String uid, Map<String, dynamic> op) async {
    final gid = op['gid'] as String;
    switch (op['kind']) {
      case 'create':
        await db.doc('groups/$gid').set({
          'members': {
            uid: {'role': 'admin', 'devices': op['devices']},
          },
          'epoch': op['epoch'],
          'fence': <Object>[],
        });
        await db.doc('users/$uid/groupRefs/$gid').set({
          'role': 'admin',
          'joinedEpoch': op['epoch'],
        });
        _watchGroup(gid);
      case 'accept':
        await db.doc('groups/$gid/invites/$uid').update({
          'status': 'accepted',
          'devices': op['devices'],
        });
      case 'decline':
        await db.doc('groups/$gid/invites/$uid').delete();
        await db.doc('users/$uid/groupInvites/$gid').delete();
    }
  }

  Future<void> _group(String gid, Map<String, dynamic> op) async {
    final groupRef = db.doc('groups/$gid');
    final group = (await groupRef.get()).data();
    if (group == null) throw _Refused('no group');
    final members = Map<String, dynamic>.from(group['members'] as Map);
    final by = op['by'] as String;
    final epoch = group['epoch'] as int;
    Future<void> commit(String kind) async {
      if (op['epoch'] != epoch) throw _Refused('epoch');
      final slot = db.doc('groups/$gid/commits/${_slot(epoch)}');
      if ((await slot.get()).exists) throw _Refused('epoch');
      await slot.set({
        'e': epoch,
        'by': by,
        'device': op['device'] ?? '',
        'kind': kind,
        'ct': op['commit'],
      });
    }

    switch (op['kind']) {
      case 'invite':
        // Any member invites (the backend also requires a 1:1 contact).
        final target = op['uid'] as String;
        await db.doc('groups/$gid/invites/$target').set({
          'by': by,
          'status': 'pending',
        });
        await db.doc('users/$target/groupInvites/$gid').set({
          'by': by,
          'at': Timestamp.now(),
        });
      case 'add':
        final target = op['uid'] as String;
        final invite = (await db.doc('groups/$gid/invites/$target').get())
            .data();
        if (invite?['status'] != 'accepted') throw _Refused('not accepted');
        await commit('membership');
        await db.doc('groups/$gid/welcomes/${target}_${_slot(epoch + 1)}').set({
          'uid': target,
          'epoch': epoch + 1,
          'ct': op['welcome'],
        });
        for (final p in (op['packages'] as List).cast<Map>()) {
          await db
              .doc(
                'users/$target/devices/${p['device']}/mlsPackages/${p['slot']}',
              )
              .delete();
        }
        members[target] = {'role': 'member', 'devices': invite!['devices']};
        await groupRef.update({'members': members, 'epoch': epoch + 1});
        await db.doc('users/$target/groupRefs/$gid').set({
          'role': 'member',
          'joinedEpoch': epoch + 1,
        });
        await db.doc('groups/$gid/invites/$target').delete();
        await db.doc('users/$target/groupInvites/$gid').delete();
      case 'leave':
        final leaving = members.remove(by) as Map;
        await db.doc('users/$by/groupRefs/$gid').delete();
        if (members.isEmpty) {
          await groupRef.delete();
          return;
        }
        // The fake merges map fields on update, so delete the key itself.
        await groupRef.update({
          'members.$by': FieldValue.delete(),
          'fence': [
            ...(group['fence'] as List),
            {'uid': by, 'devices': leaving['devices']},
          ],
        });
      case 'finalize':
        await commit('membership');
        await groupRef.update({'fence': <Object>[], 'epoch': epoch + 1});
      case 'remove':
        await commit('membership');
        await groupRef.update({
          'members.${op['uid']}': FieldValue.delete(),
          'epoch': epoch + 1,
        });
        await db.doc('users/${op['uid']}/groupRefs/$gid').delete();
    }
  }

  Future<void> close() async {
    for (final s in _subs) {
      await s.cancel();
    }
  }
}

class _Refused implements Exception {
  _Refused(this.reason);
  final String reason;
}
