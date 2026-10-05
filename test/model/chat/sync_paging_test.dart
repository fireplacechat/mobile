// Sync paging: a long backlog is read page by page, each page moving forward, and the read
// position never goes back to the durable cursor (which can be held back by an unfinished
// message). Review finding P1: "sync can continuously reopen a full page without progress".
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A history store that fails for chosen message ids, like a storage error would.
class _FlakyStore extends MemoryMessageStore {
  final failing = <String>{};
  @override
  Future<bool> has(String chatId, String messageId) async {
    if (failing.contains(messageId)) throw StateError('storage trouble');
    return super.has(chatId, messageId);
  }
}

const chat = 'chat1';

class _Rig {
  _Rig(this.db, this.secrets, this.service, this.store, this.deviceId);
  final FakeFirebaseFirestore db;
  final MemorySecretStore secrets;
  final ChatService service;
  final _FlakyStore store;
  final String deviceId;
  final seen = <String>[];

  static Future<_Rig> create() async {
    final db = FakeFirebaseFirestore();
    final secrets = MemorySecretStore();
    final keys = KeyService(db, secrets);
    final device = await keys.ensureDevice('me');
    final store = _FlakyStore();
    final service = ChatService(
      db: db,
      uid: 'me',
      device: device,
      keys: keys,
      prekeys: PreKeyService(db, secrets),
      secrets: secrets,
      messages: store,
    );
    final rig = _Rig(db, secrets, service, store, device.keys.deviceId);
    service.syncObserver = (_, ids) => rig.seen.addAll(ids);
    await db.collection('chats').doc(chat).set({
      'participants': ['me', 'peer'],
    });
    return rig;
  }

  /// A message that is "done" the moment it is seen: a peer message with no envelope for this
  /// device, which is stored as "sent before this device was added".
  Future<void> addDone(String id, Timestamp ts) =>
      db.collection('chats').doc(chat).collection('messages').doc(id).set({
        'senderUid': 'peer',
        'senderDevice': 'peer-device',
        'ts': ts,
        'envelopes': {'someone-else': {}},
      });

  Future<void> setCursor(String raw) =>
      secrets.write('cursor:$deviceId:$chat', raw);
  Future<String?> cursor() => secrets.read('cursor:$deviceId:$chat');
}

Future<void> eventually(bool Function() cond, String why) async {
  for (var i = 0; i < 200; i++) {
    if (cond()) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail('not reached: $why');
}

String id(int i) => 'm${i.toString().padLeft(5, '0')}';

void main() {
  test(
    '1,200 messages with the SAME timestamp are all reached, in 3 pages',
    () async {
      final r = await _Rig.create();
      await r.setCursor('100:0');
      final same = Timestamp(100, 0);
      for (var i = 0; i < 1200; i++) {
        await r.addDone(id(i), same);
      }
      await r.addDone('tail', Timestamp(200, 0));
      final sub = r.service.startSync(chat);
      await eventually(
        () => r.seen.contains('tail'),
        'the message after the equal-timestamp block',
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(
        r.seen.toSet().length,
        1201,
        reason: 'every message was delivered',
      );
      expect(r.seen.length, 1201, reason: 'and none was read twice');
      expect(r.service.syncPagesOpened[chat], 3, reason: '500 + 500 + 201');
      await sub.cancel();
    },
  );

  test('a full page with an UNFINISHED first message makes progress and does not loop', () async {
    final r = await _Rig.create();
    await r.setCursor('100:0');
    for (var i = 0; i < 1200; i++) {
      await r.addDone(id(i), Timestamp(100 + i, 0));
    }
    r.store.failing.add(id(0)); // the oldest message cannot be processed yet
    final sub = r.service.startSync(chat);
    await eventually(() => r.seen.contains(id(1199)), 'the newest message');
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(
      r.service.syncPagesOpened[chat],
      3,
      reason: 'no reopening of the same page',
    );
    expect(r.seen.length, r.seen.toSet().length, reason: 'nothing re-read');
    expect(r.seen.toSet().length, 1200);
    // The durable cursor is held at the unfinished message, so a restart would bring it back.
    expect(await r.cursor(), '100:0');
    await sub.cancel();
  });

  test(
    'after the backlog is drained, a new message still arrives live',
    () async {
      final r = await _Rig.create();
      await r.setCursor('100:0');
      for (var i = 0; i < 520; i++) {
        await r.addDone(id(i), Timestamp(100 + i, 0));
      }
      final sub = r.service.startSync(chat);
      await eventually(
        () => r.seen.contains(id(519)),
        'the end of the backlog',
      );
      await r.addDone('live', Timestamp(5000, 0));
      await eventually(() => r.seen.contains('live'), 'a live message');
      expect(r.seen.where((x) => x == 'live').length, 1);
      await sub.cancel();
    },
  );

  test(
    'the cursor still advances past finished messages (nothing unfinished)',
    () async {
      final r = await _Rig.create();
      await r.setCursor('100:0');
      for (var i = 0; i < 30; i++) {
        await r.addDone(id(i), Timestamp(100 + i, 0));
      }
      final sub = r.service.startSync(chat);
      await eventually(() => r.seen.length >= 30, 'all 30');
      for (var i = 0; i < 40 && await r.cursor() != '129:0'; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(await r.cursor(), '129:0');
      await sub.cancel();
    },
  );
}
