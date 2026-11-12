// The background push handler's receive (decision 0030): one read of a chat's new
// messages, the same receive path as the app, and each new message reported once,
// by whichever service saved it.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:flutter_test/flutter_test.dart';

const _chat = 'alice_bob';

class _Store extends MemoryMessageStore {
  bool failing = false;
  @override
  Future<void> add(LocalMessage m) async {
    if (failing) throw StateError('storage unavailable');
    await super.add(m);
  }
}

class _Account {
  _Account(this.uid, this.secrets, this.messages, this.device, this.hub);
  final String uid;
  final MemorySecretStore secrets;
  final _Store messages;
  final LocalDevice device;
  final MemoryLockHub hub;

  /// A service over this account's stores, as the app or the push handler
  /// opens it: its own caches, the shared lock.
  ChatService service(FakeFirebaseFirestore db) {
    final lock = SharedLock(
      gate: MemoryLockGate(hub),
      generation: hub.generation,
    );
    return ChatService(
      db: db,
      uid: uid,
      device: device,
      keys: KeyService(db, secrets),
      prekeys: PreKeyService(db, secrets, lock: lock),
      secrets: secrets,
      messages: messages,
      lock: lock,
    );
  }

  static Future<_Account> create(FakeFirebaseFirestore db, String uid) async {
    await db.collection('usernames').doc(uid).set({'uid': uid});
    await db.collection('users').doc(uid).set({'username': uid});
    final secrets = MemorySecretStore();
    final device = await KeyService(db, secrets).ensureDevice(uid);
    await PreKeyService(db, secrets).maintain(uid, device);
    return _Account(uid, secrets, _Store(), device, MemoryLockHub());
  }
}

void main() {
  late FakeFirebaseFirestore db;
  late _Account alice, bob;
  late ChatService bobApp;

  setUp(() async {
    db = FakeFirebaseFirestore();
    alice = await _Account.create(db, 'alice');
    bob = await _Account.create(db, 'bob');
    bobApp = bob.service(db);
    await bobApp.startChat('alice');
    final aliceApp = alice.service(db);
    await aliceApp.acceptRequest(_chat);
    await aliceApp.close();
  });
  tearDown(() => bobApp.close());

  Future<List<String>> bodies(_Account a) async => [
    for (final m in await a.messages.watch(_chat).first) m.body,
  ];

  test('receives new messages once and reports each one', () async {
    await bobApp.sendText(_chat, 'hello');
    await bobApp.sendText(_chat, 'are you there?');
    final background = alice.service(db);
    final arrived = <LocalMessage>[];
    final sub = background.arrivals.listen(arrived.add);
    expect(await background.receiveOnce(_chat, upkeep: false), isTrue);
    await pumpEventQueue();
    await sub.cancel();
    await background.close();
    expect([for (final m in arrived) m.body], ['hello', 'are you there?']);
    expect(arrived.every((m) => m.senderUid == 'bob'), isTrue);
    expect(await bodies(alice), ['hello', 'are you there?']);

    // The app starts later: nothing is received or reported twice.
    final app = alice.service(db);
    final again = <LocalMessage>[];
    final appSub = app.arrivals.listen(again.add);
    final sync = app.startSync(_chat);
    await bobApp.sendText(_chat, 'third');
    for (var i = 0; i < 100 && again.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await sync.cancel();
    await appSub.cancel();
    await app.close();
    expect([for (final m in again) m.body], ['third']);
    expect(await bodies(alice), ['hello', 'are you there?', 'third']);
  });

  test('a second run finds nothing new and reports nothing', () async {
    await bobApp.sendText(_chat, 'once');
    final first = alice.service(db);
    expect(await first.receiveOnce(_chat), isTrue);
    await first.close();
    final second = alice.service(db);
    final arrived = <LocalMessage>[];
    final sub = second.arrivals.listen(arrived.add);
    expect(await second.receiveOnce(_chat), isTrue);
    await pumpEventQueue();
    await sub.cancel();
    await second.close();
    expect(arrived, isEmpty);
    expect(await bodies(alice), ['once']);
  });

  test(
    'the app and the handler receiving at once save each message once',
    () async {
      for (var i = 0; i < 5; i++) {
        await bobApp.sendText(_chat, 'm$i');
      }
      final app = alice.service(db);
      final background = alice.service(db);
      final reported = <String>[];
      final subs = [
        app.arrivals.listen((m) => reported.add(m.body)),
        background.arrivals.listen((m) => reported.add(m.body)),
      ];
      final sync = app.startSync(_chat);
      await background.receiveOnce(_chat);
      for (var i = 0; i < 100 && reported.length < 5; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await sync.cancel();
      for (final s in subs) {
        await s.cancel();
      }
      await app.close();
      await background.close();
      expect(reported..sort(), ['m0', 'm1', 'm2', 'm3', 'm4']);
      expect(await bodies(alice), ['m0', 'm1', 'm2', 'm3', 'm4']);
      // Both still talk to bob afterwards: no session went back.
      final later = alice.service(db);
      await later.sendText(_chat, 'reply');
      await later.close();
      final bobSync = bobApp.startSync(_chat);
      for (var i = 0; i < 100 && !(await bodies(bob)).contains('reply'); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await bobSync.cancel();
      expect(
        (await bob.messages.watch(_chat).first)
            .firstWhere((m) => m.body == 'reply')
            .status,
        MessageStatus.ok,
      );
    },
  );

  test('an unreadable message is reported; my own are not', () async {
    await bobApp.sendText(_chat, 'readable');
    await db.collection('chats').doc(_chat).collection('messages').add({
      'senderUid': 'bob',
      'senderDevice': bob.device.keys.deviceId,
      'ts': Timestamp.fromDate(DateTime.now().add(const Duration(seconds: 5))),
      'envelopes': {'another-device': {}},
    });
    final background = alice.service(db);
    final arrived = <LocalMessage>[];
    final sub = background.arrivals.listen(arrived.add);
    expect(await background.receiveOnce(_chat), isTrue);
    await pumpEventQueue();
    await sub.cancel();
    await background.close();
    expect(
      [for (final m in arrived) m.status],
      [MessageStatus.ok, MessageStatus.undecryptable],
    );

    // Bob's own handler sees bob's sends: nothing to report.
    final bobBackground = bob.service(db);
    final own = <LocalMessage>[];
    final ownSub = bobBackground.arrivals.listen(own.add);
    await bobBackground.receiveOnce(_chat);
    await pumpEventQueue();
    await ownSub.cancel();
    await bobBackground.close();
    expect(own, isEmpty);
  });

  test('a message that cannot be saved yet makes it return false', () async {
    await bobApp.sendText(_chat, 'held back');
    alice.messages.failing = true;
    final background = alice.service(db);
    final arrived = <LocalMessage>[];
    final sub = background.arrivals.listen(arrived.add);
    expect(await background.receiveOnce(_chat), isFalse);
    await pumpEventQueue();
    await sub.cancel();
    await background.close();
    expect(arrived, isEmpty);

    // Nothing was spent: the next run receives it.
    alice.messages.failing = false;
    final next = alice.service(db);
    expect(await next.receiveOnce(_chat), isTrue);
    await next.close();
    expect(await bodies(alice), ['held back']);
  });
}
