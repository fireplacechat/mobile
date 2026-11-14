import 'dart:async';

import 'package:fireplace/fireplace_services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pending_firestore.dart';

void main() {
  for (final refused in [false, true]) {
    test('unblock waits for server confirmation, refused=$refused', () async {
      final db = PendingFirestore();
      final blocks = db.collection('users/alice/blocks');
      blocks.emit(PendingSnapshot([PendingMessage('bob', {})]));
      final safety = SafetyService(db, MemorySecretStore(), 'alice');
      await safety.start();
      addTearDown(db.close);
      addTearDown(safety.dispose);
      await pumpEventQueue();
      final began = Completer<void>();
      final answer = Completer<void>();
      db.onDelete = (_) async {
        // Firestore's local delete echo arrives before its server answer.
        blocks.emit(PendingSnapshot(const [], pending: true));
        began.complete();
        try {
          await answer.future;
        } catch (_) {
          blocks.emit(PendingSnapshot([PendingMessage('bob', {})]));
          rethrow;
        }
      };
      final unblock = safety.unblock('bob');
      final outcome = expectLater(
        unblock,
        refused ? throwsStateError : completes,
      );
      await began.future;
      await pumpEventQueue();
      final remainedBlocked = safety.isBlocked('bob');
      if (refused) {
        answer.completeError(StateError('server refused'));
      } else {
        answer.complete();
      }
      await outcome;
      if (refused) {
        // Platform callbacks can already be queued when the write future
        // rejects. A late optimistic echo still must not lift the block.
        blocks.emit(PendingSnapshot(const [], pending: true));
        await pumpEventQueue();
      }
      expect(
        remainedBlocked,
        isTrue,
        reason: 'a local delete must not resume messaging before the server',
      );
      expect(safety.isBlocked('bob'), refused);
      expect(blocks.metadataChanges, isTrue);
    });
  }

  test('a later block waits for an unfinished unblock and wins', () async {
    final db = PendingFirestore();
    final blocks = db.collection('users/alice/blocks');
    blocks.emit(PendingSnapshot([PendingMessage('bob', {})]));
    final safety = SafetyService(db, MemorySecretStore(), 'alice');
    await safety.start();
    addTearDown(db.close);
    addTearDown(safety.dispose);
    final began = Completer<void>();
    final answer = Completer<void>();
    final writes = <String>[];
    db.onDelete = (_) async {
      writes.add('unblock');
      began.complete();
      await answer.future;
      blocks.emit(PendingSnapshot(const []));
    };
    db.onSet = (_) async {
      writes.add('block');
      blocks.emit(PendingSnapshot([PendingMessage('bob', {})]));
    };
    final unblock = safety.unblock('bob');
    await began.future;
    final block = safety.block('bob');
    await pumpEventQueue();
    final beforeAnswer = List.of(writes);
    answer.complete();
    await Future.wait([unblock, block]);
    await pumpEventQueue();
    expect(beforeAnswer, ['unblock']);
    expect(writes, ['unblock', 'block']);
    expect(safety.isBlocked('bob'), isTrue);
  });

  test('a pending unblock does not delay blocking somebody else', () async {
    final db = PendingFirestore();
    final blocks = db.collection('users/alice/blocks');
    blocks.emit(PendingSnapshot([PendingMessage('bob', {})]));
    final safety = SafetyService(db, MemorySecretStore(), 'alice');
    await safety.start();
    addTearDown(db.close);
    addTearDown(safety.dispose);
    final began = Completer<void>();
    final answer = Completer<void>();
    var blockedCarol = false;
    db.onDelete = (_) async {
      began.complete();
      await answer.future;
    };
    db.onSet = (path) async {
      expect(path, 'users/alice/blocks/carol');
      blockedCarol = true;
      blocks.emit(
        PendingSnapshot([PendingMessage('carol', {})], pending: true),
      );
    };
    final unblock = safety.unblock('bob');
    await began.future;
    final block = safety.block('carol');
    await pumpEventQueue();
    final blockedBeforeAnswer = blockedCarol;
    answer.complete();
    await Future.wait([unblock, block]);
    expect(blockedBeforeAnswer, isTrue);
    expect(safety.isBlocked('carol'), isTrue);
  });
}
