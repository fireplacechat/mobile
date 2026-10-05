// Randomised end-to-end simulation of the chat SERVICE layer (everything around the
// ratchet): Firestore sync and catch-up, the send write-ahead, the receive journal,
// deferral and retry, several devices per account, devices linked mid-conversation,
// app restarts, offline periods, and injected failures.
//
// Each run builds two accounts (one device each, up to two), then executes a seeded random
// schedule of actions. At the end every failure is cleared and the system must converge:
//
//   1. Every message that was published reaches EVERY device that existed when it was sent
//      (the other account's devices and the sender's own other devices), exactly once, with
//      the right text.  Nothing is silently lost or turned into "could not decrypt".
//   2. No device shows a message that was never published, or any message twice.
//   3. The only unreadable entries allowed are "sent before this device was added", and
//      only on devices linked after the message was sent.
//   4. A message whose send was reported as failed for certain (definite publish failure,
//      storage failure before publishing) never appears anywhere.
//   5. The conversation is not stuck: afterwards each device can send and everyone gets it.
//
// Reproduce a failure:
//   flutter test test/services/chat_simulation_test.dart --dart-define=SIM_SEED=<seed>
// Run more / longer:  --dart-define=SIM_RUNS=60 --dart-define=SIM_STEPS=60
// (Scheduling of background sync is not perfectly deterministic, so a seed reproduces the
// action sequence, and usually, but not always, the same failure.)

import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_crypto.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:flutter_test/flutter_test.dart';

const _runs = int.fromEnvironment('SIM_RUNS', defaultValue: 6);
const _onlySeed = int.fromEnvironment('SIM_SEED', defaultValue: -1);
const _steps = int.fromEnvironment('SIM_STEPS', defaultValue: 36);

class FlakySecrets extends MemorySecretStore {
  String? prefix;
  int times = 0;
  @override
  Future<void> write(String key, String value) async {
    if (prefix != null && key.startsWith(prefix!) && times > 0) {
      times--;
      throw StateError('secure storage unavailable');
    }
    await super.write(key, value);
  }
}

class FlakyMessages extends MemoryMessageStore {
  int times = 0;
  @override
  Future<void> add(LocalMessage m) async {
    if (times > 0) {
      times--;
      throw StateError('message store unavailable');
    }
    await super.add(m);
  }
}

/// A storage handle that stops working when its process is "killed", so a restarted app
/// can never have its previous instance still writing in the background.
class GuardedSecrets implements SecretStore {
  GuardedSecrets(this.inner);
  final SecretStore inner;
  bool dead = false;
  void _check() {
    if (dead) throw StateError('process killed');
  }

  @override
  Future<String?> read(String key) async {
    _check();
    return inner.read(key);
  }

  @override
  Future<void> write(String key, String value) async {
    _check();
    await inner.write(key, value);
  }

  @override
  Future<void> delete(String key) async {
    _check();
    await inner.delete(key);
  }

  @override
  Future<void> clear() async {
    _check();
    await inner.clear();
  }
}

class GuardedMessages implements LocalMessageStore {
  GuardedMessages(this.inner);
  final LocalMessageStore inner;
  bool dead = false;
  void _check() {
    if (dead) throw StateError('process killed');
  }

  @override
  Future<bool> has(String chatId, String messageId) async {
    _check();
    return inner.has(chatId, messageId);
  }

  @override
  Future<void> add(LocalMessage m) async {
    _check();
    await inner.add(m);
  }

  @override
  Future<LocalMessage?> get(String chatId, String messageId) async {
    _check();
    return inner.get(chatId, messageId);
  }

  @override
  Future<void> remove(String chatId, String messageId) async {
    _check();
    await inner.remove(chatId, messageId);
  }

  @override
  Future<void> deleteChat(String chatId) async {
    _check();
    await inner.deleteChat(chatId);
  }

  @override
  Stream<List<LocalMessage>> watch(String chatId) => inner.watch(chatId);
}

enum PublishMode {
  normal,
  definiteFail,
  lostBeforeCommit,
  committedButReportedLost,
}

class Phone {
  Phone(this.db, this.uid, this.label, this.secrets, this.messages, this.keys);
  final FakeFirebaseFirestore db;
  final String uid;
  final String label;
  final FlakySecrets secrets;
  final FlakyMessages messages;
  late KeyService keys;
  late LocalDevice device;
  late PreKeyService prekeys;
  GuardedSecrets? _gs;
  GuardedMessages? _gm;
  late ChatService chat;
  StreamSubscription<void>? sub;
  bool online = true;
  PublishMode mode = PublishMode.normal;
  int linkedAtMessage =
      0; // number of messages published before this device existed

  static Future<Phone> first(FakeFirebaseFirestore db, String uid) async {
    final secrets = FlakySecrets();
    final p = Phone(
      db,
      uid,
      '${uid}1',
      secrets,
      FlakyMessages(),
      KeyService(db, secrets),
    );
    p.device = await p.keys.ensureDevice(uid);
    p.prekeys = PreKeyService(db, secrets);
    await p.prekeys.maintain(uid, p.device);
    p.restart();
    return p;
  }

  /// Another device of an existing account (stand-in for the link flow).
  static Future<Phone> linked(
    FakeFirebaseFirestore db,
    Phone existing,
    int published,
  ) async {
    final secrets = FlakySecrets();
    final identity = existing.device.identity;
    final dk = await DeviceKeys.generate();
    final bundle = await dk.certify(identity, existing.uid);
    await db
        .collection('users')
        .doc(existing.uid)
        .collection('devices')
        .doc(dk.deviceId)
        .set({
          ...bundle.toFirestore(),
          'createdAt': FieldValue.serverTimestamp(),
        });
    final p = Phone(
      db,
      existing.uid,
      '${existing.uid}2',
      secrets,
      FlakyMessages(),
      KeyService(db, secrets),
    );
    p.device = LocalDevice(identity, dk, bundle);
    p.prekeys = PreKeyService(db, secrets);
    await p.prekeys.maintain(existing.uid, p.device);
    p.linkedAtMessage = published;
    p.restart();
    return p;
  }

  /// Kills the running app instance and starts a new one over the same stored data, like a
  /// crash or restart: anything the old instance still had in flight can no longer write.
  void restart() {
    _gs?.dead = true;
    _gm?.dead = true;
    final gs = _gs = GuardedSecrets(secrets);
    final gm = _gm = GuardedMessages(messages);
    keys = KeyService(db, gs);
    prekeys = PreKeyService(db, gs);
    chat = _service(gs, gm);
  }

  ChatService _service(GuardedSecrets gs, GuardedMessages gm) => ChatService(
    db: db,
    uid: uid,
    device: device,
    keys: keys,
    prekeys: prekeys,
    secrets: gs,
    messages: gm,
    commitBatch: (b) async {
      switch (mode) {
        case PublishMode.normal:
          await b.commit();
        case PublishMode.definiteFail:
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
          );
        case PublishMode.lostBeforeCommit:
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'unavailable',
          );
        case PublishMode.committedButReportedLost:
          await b.commit();
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'unavailable',
          );
      }
    },
  );

  void startSyncing(String chatId) {
    sub?.cancel();
    sub = chat.startSync(chatId);
  }

  void stopSyncing() {
    sub?.cancel();
    sub = null;
  }

  Future<List<LocalMessage>> history(String chatId) =>
      messages.watch(chatId).first;
}

class Published {
  Published(this.text, this.sender, this.index);
  final String text;
  final Phone sender;
  final int index; // order of publication
  bool senderSawSuccess = false;
}

Future<void> simulate(int seed) async {
  final rnd = Random(seed);
  final db = FakeFirebaseFirestore();
  const chatId = 'alice_bob';
  for (final u in ['alice', 'bob']) {
    await db.collection('usernames').doc(u).set({'uid': u});
    await db.collection('users').doc(u).set({'username': u});
  }
  final staleMode =
      rnd.nextInt(3) == 0; // replace unanswered sessions at every send
  final savedStale = ChatService.staleSessionAfter;
  if (staleMode) ChatService.staleSessionAfter = Duration.zero;

  final trace = <String>[];
  String why(String m) =>
      'seed $seed, step ${trace.length}${staleMode ? ' (stale-session mode)' : ''}: $m\n  trace: ${trace.join(' | ')}';
  Never fail(String m) => throw TestFailure(why(m));

  final phones = <Phone>[];
  final published = <Published>[]; // messages that exist on the server
  final mustNotExist = <String>{}; // texts whose send definitely failed
  var attempt = 0;

  try {
    final alice = await Phone.first(db, 'alice');
    final bob = await Phone.first(db, 'bob');
    phones.addAll([alice, bob]);
    await alice.chat.startChat('bob');
    await bob.chat.acceptRequest(chatId);
    for (final p in phones) {
      p.startSyncing(chatId);
    }

    Phone pick() => phones[rnd.nextInt(phones.length)];

    Future<int> publishedBy(Phone p) async {
      final snap = await db
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .get();
      for (final d in snap.docs) {
        // Retention: every published message expires about 30 days after it was sent.
        final expire = d.data()['expireAt'];
        expect(
          expire,
          isA<Timestamp>(),
          reason: 'message ${d.id} has no expireAt',
        );
        final days =
            (expire as Timestamp).toDate().difference(DateTime.now()).inHours /
            24;
        expect(
          days,
          inInclusiveRange(29.5, 30.1),
          reason: 'expireAt is ${days.toStringAsFixed(2)} days out',
        );
      }
      return snap.docs
          .where((d) => d.data()['senderDevice'] == p.device.keys.deviceId)
          .length;
    }

    Future<void> send(Phone p, {bool crash = false}) async {
      attempt++;
      final text = 'msg$attempt-${p.label}-${rnd.nextInt(1 << 30)}';
      final r = rnd.nextInt(100);
      var note = 'ok';
      p.mode = PublishMode.normal;
      if (r >= 70 && r < 78) {
        p.mode = PublishMode.definiteFail;
        note = 'definiteFail';
      } else if (r >= 78 && r < 85) {
        p.mode = PublishMode.lostBeforeCommit;
        note = 'lostBeforeCommit';
      } else if (r >= 85 && r < 92) {
        p.mode = PublishMode.committedButReportedLost;
        note = 'committedButReportedLost';
      } else if (r >= 92) {
        p.secrets.prefix = 'sess:';
        p.secrets.times =
            1; // storage fails while saving the write-ahead ratchets
        note = 'storageFault';
      }
      // Whether the message exists is decided by the server, not by what the app reported:
      // a failure can come after the message was already published.
      if (crash) note = 'crash';
      final faultPending =
          note != 'ok' || p.secrets.times > 0 || p.messages.times > 0;
      final before = await publishedBy(p);
      Object? error;
      try {
        final sending = p.chat.sendText(chatId, text);
        if (crash) {
          // the app is killed part-way through the send
          await Future<void>.delayed(Duration(milliseconds: rnd.nextInt(40)));
          p.stopSyncing();
          p.restart();
          if (p.online) p.startSyncing(chatId);
        }
        await sending;
      } catch (e) {
        error = e;
      }
      p.mode = PublishMode.normal;
      final exists = (await publishedBy(p)) > before;
      if (error == null && !exists) {
        fail('send by ${p.label} reported success but published nothing');
      }
      if (error != null && !faultPending) {
        fail('send by ${p.label} failed with no fault pending: $error');
      }
      if (exists) {
        published.add(
          Published(text, p, published.length)
            ..senderSawSuccess = error == null,
        );
      } else {
        mustNotExist.add(text);
      }
      trace.add(
        'send(${p.label}:${error == null ? 'ok' : 'error'}${exists ? '' : ',not-published'}${note == 'ok' ? '' : ',$note'})',
      );
    }

    for (var step = 0; step < _steps; step++) {
      final r = rnd.nextInt(100);
      if (r < 34) {
        await send(pick(), crash: rnd.nextInt(7) == 0);
      } else if (r < 40) {
        // both accounts send at the same moment (including the very first messages)
        final a = phones.firstWhere((p) => p.uid == 'alice');
        final b = phones.firstWhere((p) => p.uid == 'bob');
        trace.add('simultaneous(${a.label},${b.label})');
        await Future.wait([send(a), send(b)]);
      } else if (r < 50) {
        final p = pick();
        if (p.online) {
          p.stopSyncing();
          p.online = false;
          trace.add('offline(${p.label})');
        } else {
          p.online = true;
          p.startSyncing(chatId);
          trace.add('online(${p.label})');
        }
      } else if (r < 60) {
        final p = pick();
        p.stopSyncing();
        p.restart(); // crash/restart: in-memory state (deferred retries) is lost
        if (p.online) p.startSyncing(chatId);
        trace.add('restart(${p.label})');
      } else if (r < 68) {
        final p = pick();
        if (rnd.nextBool()) {
          p.secrets.prefix = const [
            'sess:',
            'journal',
            'cursor',
            'sess:',
          ][rnd.nextInt(4)];
          p.secrets.times = 1 + rnd.nextInt(2);
        } else {
          p.messages.times = 1 + rnd.nextInt(2);
        }
        trace.add('storageFault(${p.label})');
      } else if (r < 74) {
        final p = pick();
        await p.chat.retryDeferred();
        trace.add('retry(${p.label})');
      } else if (r < 78) {
        final p = pick();
        await p.secrets.delete('cursor:${p.device.keys.deviceId}:$chatId');
        trace.add('loseCursor(${p.label})');
      } else if (r < 83) {
        final p = pick();
        await p.prekeys.maintain(p.uid, p.device);
        trace.add('maintainPrekeys(${p.label})');
      } else if (r < 89) {
        final uid = rnd.nextBool() ? 'alice' : 'bob';
        final mine = phones.where((p) => p.uid == uid).toList();
        if (mine.length < 2) {
          final p = await Phone.linked(db, mine.first, published.length);
          phones.add(p);
          p.startSyncing(chatId);
          trace.add('link(${p.label} after ${published.length} messages)');
        }
      } else {
        await Future<void>.delayed(Duration(milliseconds: 5 + rnd.nextInt(40)));
        trace.add('pause');
      }
    }

    // ---- heal: clear every fault, bring everyone online, restart, let it converge ----
    for (final p in phones) {
      p.mode = PublishMode.normal;
      p.secrets.times = 0;
      p.messages.times = 0;
      p.online = true;
      p.stopSyncing();
      p.restart();
      p.startSyncing(chatId);
    }
    trace.add('HEAL');

    Future<String?> check() async {
      final texts = {for (final x in published) x.text};
      for (final p in phones) {
        final hist = await p.history(chatId);
        final byBody = <String, List<LocalMessage>>{};
        for (final m in hist) {
          byBody.putIfAbsent(m.body, () => []).add(m);
        }
        for (final x in published) {
          final copies = byBody[x.text] ?? const <LocalMessage>[];
          final shouldHave = identical(p, x.sender)
              ? x.senderSawSuccess
              : x.index >= p.linkedAtMessage;
          if (identical(p, x.sender)) {
            if (copies.length > 1) {
              return '${p.label} has "${x.text}" ${copies.length} times';
            }
            if (x.senderSawSuccess && copies.isEmpty) {
              return '${p.label} lost its own sent message "${x.text}"';
            }
            if (copies.isNotEmpty && !copies.single.outgoing) {
              return '${p.label} shows own message as incoming';
            }
          } else if (shouldHave) {
            if (copies.isEmpty) {
              return '${p.label} has not received "${x.text}" (message #${x.index} from ${x.sender.label})';
            }
            if (copies.length > 1) {
              return '${p.label} has "${x.text}" ${copies.length} times';
            }
            if (copies.single.status != MessageStatus.ok) {
              return '${p.label}: "${x.text}" is ${copies.single.status}';
            }
            if (copies.single.outgoing) {
              return '${p.label} shows incoming message as outgoing';
            }
          } else if (copies.isNotEmpty) {
            return '${p.label} (added after message #${x.index}) can read "${x.text}"';
          }
        }
        for (final m in hist) {
          if (m.status == MessageStatus.unconfirmed) {
            // A warning about an ambiguous send of OUR OWN message, never a received one.
            if (!m.outgoing || m.senderDevice != p.device.keys.deviceId) {
              return '${p.label} has a "not confirmed" entry that is not its own send: "${m.body}"';
            }
            // If the message did reach the server, sync must have turned the warning into an
            // ordinary sent message by itself.
            if (texts.contains(m.body)) {
              return '${p.label}: published message "${m.body}" is still marked not confirmed';
            }
            continue;
          }
          if (m.status == MessageStatus.ok) {
            if (!texts.contains(m.body)) {
              return '${p.label} shows "${m.body}" which was never published';
            }
            if (mustNotExist.contains(m.body)) {
              return '${p.label} shows "${m.body}" whose send had definitely failed';
            }
          } else if (m.body != 'Sent before this device was added.') {
            return '${p.label} has an unreadable message: "${m.body}"';
          }
        }
        final placeholders = hist
            .where(
              (m) =>
                  m.status != MessageStatus.ok &&
                  m.status != MessageStatus.unconfirmed,
            )
            .length;
        if (placeholders > p.linkedAtMessage + 0) {
          // placeholders only for messages published before the device existed (the
          // count of ambiguous-but-committed ones is included in linkedAtMessage)
          return '${p.label} has $placeholders placeholders but was added after only ${p.linkedAtMessage} messages';
        }
      }
      return null;
    }

    String? last;
    final deadline = DateTime.now().add(const Duration(seconds: 25));
    while (true) {
      for (final p in phones) {
        await p.chat.retryDeferred();
      }
      last = await check();
      if (last == null || DateTime.now().isAfter(deadline)) break;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    if (last != null) {
      final snap = await db
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .get();
      final lines = <String>[];
      for (final p in phones) {
        final have = {for (final m in await p.history(chatId)) m.id: m};
        final cursor = await p.secrets.read(
          'cursor:${p.device.keys.deviceId}:$chatId',
        );
        final missing = [
          for (final d in snap.docs)
            if (!have.containsKey(d.id) &&
                (d.data()['envelopes'] as Map).containsKey(
                  p.device.keys.deviceId,
                ) &&
                d.data()['senderDevice'] != p.device.keys.deviceId)
              '${d.id.substring(0, 5)}@${(d.data()['ts'] as Timestamp?)?.nanoseconds} from ${d.data()['senderDevice'].toString().substring(0, 4)}',
        ];
        final bad = [
          for (final m in have.values)
            if (m.status != MessageStatus.ok)
              '${m.id.substring(0, 5)}: ${m.body}',
        ];
        lines.add(
          '${p.label}: cursor=$cursor have=${have.length} missing=$missing unreadable=$bad',
        );
      }
      // detailed envelope history for every message that ended up unreadable
      for (final p in phones) {
        final hist = {for (final m in await p.history(chatId)) m.id: m};
        for (final m in hist.values.where(
          (m) =>
              m.body.startsWith('Could not decrypt') ||
              m.body == 'Missing session.',
        )) {
          final sender = m.senderDevice;
          lines.add(
            '--- ${p.label}: ${m.id.substring(0, 5)} (${m.body}) from device ${sender.substring(0, 4)}; envelopes for ${p.label}, oldest first:',
          );
          final docs =
              snap.docs
                  .where((d) => d.data()['senderDevice'] == sender)
                  .toList()
                ..sort(
                  (a, b) => (a.data()['ts'] as Timestamp).compareTo(
                    b.data()['ts'] as Timestamp,
                  ),
                );
          for (final d in docs) {
            final raw = (d.data()['envelopes'] as Map)[p.device.keys.deviceId];
            if (raw == null) continue;
            final e = Map<String, dynamic>.from(raw as Map);
            final h = hist[d.id];
            lines.add(
              '    ${d.id.substring(0, 5)} sid=${(e['sid'] as String).substring(0, 6)} n=${e['n']} pn=${e['pn']} rx=${(e['rx'] as String).substring(0, 5)} hs=${e['hs'] != null} -> ${h == null
                  ? 'NOT STORED'
                  : h.status == MessageStatus.ok
                  ? 'ok'
                  : h.body}',
            );
          }
        }
      }
      fail('did not converge: $last\n  ${lines.join('\n  ')}');
    }

    // ---- liveness: the conversation is not stuck ----
    for (final p in phones) {
      final text = 'final-${p.label}-${rnd.nextInt(1 << 30)}';
      await p.chat.sendText(chatId, text);
      published.add(
        Published(text, p, published.length)..senderSawSuccess = true,
      );
    }
    final deadline2 = DateTime.now().add(const Duration(seconds: 25));
    while (true) {
      for (final p in phones) {
        await p.chat.retryDeferred();
      }
      last = await check();
      if (last == null || DateTime.now().isAfter(deadline2)) break;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    if (last != null) fail('conversation stuck after healing: $last');
  } finally {
    ChatService.staleSessionAfter = savedStale;
    for (final p in phones) {
      await p.sub?.cancel();
    }
  }
}

void main() {
  final seeds = _onlySeed >= 0
      ? [_onlySeed]
      : [for (var i = 1; i <= _runs; i++) 5000 + i];
  for (final seed in seeds) {
    test(
      'random schedule, seed $seed',
      () => simulate(seed),
      timeout: const Timeout(Duration(minutes: 4)),
    );
  }
}
