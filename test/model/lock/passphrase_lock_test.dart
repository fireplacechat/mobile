// The optional passphrase lock (decision 0033): turning it on wraps what opens
// data, a wrong passphrase opens nothing, and turning it on or off finishes
// after being stopped at any point.
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:fireplace/src/db/account_erasure.dart';
import 'package:fireplace/src/db/secret_store.dart';
import 'package:fireplace/src/db/wrapping_secret_store.dart';
import 'package:fireplace/src/model/lock/passphrase_lock.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for Argon2id, which takes a second: the same inputs give the
/// same key, and any change gives another.
Future<List<int>> fastDerive(
  String passphrase,
  List<int> salt,
  LockParameters p,
  List<int> secret,
) async => (await Hmac.sha256().calculateMac(
  utf8.encode('$passphrase|${p.memory}|${p.iterations}|${base64Encode(salt)}'),
  secretKey: SecretKey(secret),
)).bytes;

/// Fails every write after [allowed] of them, as if the app were stopped.
class StoppingStore extends MemorySecretStore {
  int? allowed;
  @override
  Future<void> write(String key, String value) async {
    if (allowed != null) {
      if (allowed == 0) throw StateError('stopped');
      allowed = allowed! - 1;
    }
    return super.write(key, value);
  }
}

void main() {
  const uid = 'alice', device = 'dev1', passphrase = 'correct horse';
  late StoppingStore inner;
  late WrappingSecretStore store;
  late PassphraseLock lock;
  var calibrations = 0;

  PassphraseLock newLock(WrappingSecretStore s) => PassphraseLock(
    s,
    derive: fastDerive,
    calibrate: () async {
      calibrations++;
      return LockParameters.floor;
    },
  );

  final existing = {
    'msgkey:alice': 'history-key',
    'identity:alice': '{"private":"id"}',
    'device:alice': '{"deviceId":"dev1"}',
    'prekeys:alice:dev1': '{"signed":[]}',
    'sess:dev1:bob:dev9': '[{"sid":"s1"}]',
    'chatprefskey:alice': 'prefs-key',
    'groupkey:alice': 'group-key',
    'cursor:dev1:alice_bob': '12:0',
    'bundle:alice': '{"deviceId":"dev1"}',
    // Another account on the same phone is left alone.
    'identity:bob': '{"private":"bob"}',
  };

  setUp(() {
    calibrations = 0;
    inner = StoppingStore()..data.addAll(existing);
    store = WrappingSecretStore(inner);
    lock = newLock(store);
  });

  Future<void> none(Future<void> Function() work) => work();

  Future<void> turnOn() => lock.enable(
    uid: uid,
    deviceId: device,
    passphrase: passphrase,
    exclusive: none,
  );

  Future<void> expectReadable() async {
    for (final e in existing.entries) {
      expect(await store.read(e.key), e.value, reason: e.key);
    }
  }

  void expectWrapped(bool wrapped) {
    for (final name in existing.keys) {
      final raw = inner.data[name]!;
      final shouldBe = wrapped && lockWrapsItem(name, uid, device);
      expect(raw.startsWith(wrappedSecretPrefix), shouldBe, reason: name);
    }
  }

  test('turning it on wraps what opens data and turns previews off', () async {
    await turnOn();
    expectWrapped(true);
    await expectReadable();
    expect(inner.data['pushnopreview:alice'], '1');
    final r = (await lock.record(uid))!;
    expect(r.pending, isNull);
    expect(r.previewsWereOn, isTrue);
    expect(r.autoLock, AutoLock.fiveMinutes);
    // Nothing in the readable record or the secret is the passphrase.
    expect(inner.data['passlock:alice'], isNot(contains(passphrase)));
  });

  test('locked, nothing wrapped can be read; a wrong passphrase opens '
      'nothing', () async {
    await turnOn();
    lock.lock();
    await expectLater(
      store.read('msgkey:alice'),
      throwsA(isA<SecretsLocked>()),
    );
    expect(await store.read('cursor:dev1:alice_bob'), '12:0');
    expect(await lock.unlock(uid, 'wrong passphrase'), isFalse);
    expect(lock.isOpen(uid), isFalse);
    expect(await lock.unlock(uid, passphrase), isTrue);
    await expectReadable();
    // The parameters measured when it was turned on are reused.
    expect(calibrations, 1);
  });

  test(
    'a new passphrase opens the same data; the old one no longer does',
    () async {
      await turnOn();
      final before = Map.of(inner.data)..remove('passlock:alice');
      expect(await lock.change(uid, 'not it', 'a new phrase'), isFalse);
      expect(await lock.change(uid, passphrase, 'a new phrase'), isTrue);
      lock.lock();
      expect(await lock.unlock(uid, passphrase), isFalse);
      expect(await lock.unlock(uid, 'a new phrase'), isTrue);
      await expectReadable();
      // Only the record changed: the items were not rewritten.
      expect(Map.of(inner.data)..remove('passlock:alice'), before);
    },
  );

  test('turning it off puts everything back, previews included', () async {
    await turnOn();
    await lock.disable(uid, exclusive: none);
    expectWrapped(false);
    expect(store.isOpen, isFalse);
    await expectReadable();
    expect(inner.data.containsKey('passlock:alice'), isFalse);
    expect(inner.data.containsKey('passlockpepper:alice'), isFalse);
    expect(inner.data.containsKey('pushnopreview:alice'), isFalse);
  });

  test('previews someone had turned off stay off afterwards', () async {
    inner.data['pushnopreview:alice'] = '1';
    await turnOn();
    expect((await lock.record(uid))!.previewsWereOn, isFalse);
    await lock.disable(uid, exclusive: none);
    expect(inner.data['pushnopreview:alice'], '1');
  });

  test('a short passphrase is refused', () async {
    await expectLater(
      lock.enable(
        uid: uid,
        deviceId: device,
        passphrase: 'short',
        exclusive: none,
      ),
      throwsArgumentError,
    );
    expect(inner.data.containsKey('passlock:alice'), isFalse);
  });

  for (var stop = 0; stop < 12; stop++) {
    test('turning it on, stopped after $stop writes, finishes on the next '
        'unlock', () async {
      inner.allowed = stop;
      try {
        await turnOn();
      } catch (_) {}
      inner.allowed = null;
      // The app starts again: a new store and lock, nothing held.
      store = WrappingSecretStore(inner);
      lock = newLock(store);
      final r = await lock.record(uid);
      if (r == null) {
        // Stopped before the record: nothing is wrapped, and it can be
        // turned on again.
        expectWrapped(false);
        await turnOn();
      } else {
        expect(await lock.unlock(uid, passphrase), isTrue);
        await lock.finishPending(uid, exclusive: none);
      }
      expect((await lock.record(uid))!.pending, isNull);
      expectWrapped(true);
      await expectReadable();
    });

    test('turning it off, stopped after $stop writes, finishes on the next '
        'unlock', () async {
      await turnOn();
      inner.allowed = stop;
      try {
        await lock.disable(uid, exclusive: none);
      } catch (_) {}
      inner.allowed = null;
      store = WrappingSecretStore(inner);
      lock = newLock(store);
      if (await lock.record(uid) != null) {
        expect(await lock.unlock(uid, passphrase), isTrue);
        await lock.finishPending(uid, exclusive: none);
        // Stopped before it began: still on, and turning it off works.
        if (await lock.record(uid) != null) {
          await lock.disable(uid, exclusive: none);
        }
      }
      expect(await lock.record(uid), isNull);
      expectWrapped(false);
      await expectReadable();
    });
  }

  test(
    'erasing the account while locked removes all of it, and only it',
    () async {
      await turnOn();
      lock.lock();
      await eraseAccountSecrets(store, uid);
      expect(inner.data.keys.where((k) => k.contains('alice')), isEmpty);
      expect(inner.data.keys.where((k) => k.contains('dev1')), isEmpty);
      expect(inner.data['identity:bob'], existing['identity:bob']);
    },
  );

  test('the real derivation: Argon2id then the device secret', () async {
    final salt = List.filled(16, 1), secret = List.filled(32, 2);
    final a = await deriveLockKey(
      passphrase,
      salt,
      LockParameters.floor,
      secret,
    );
    expect(a, hasLength(32));
    expect(
      await deriveLockKey(passphrase, salt, LockParameters.floor, secret),
      a,
    );
    expect(
      await deriveLockKey(
        passphrase,
        salt,
        LockParameters.floor,
        List.filled(32, 3),
      ),
      isNot(a),
    );
    final p = await calibrateLock(
      memoryTarget: Duration.zero,
      target: Duration.zero,
    );
    expect(p.memory, LockParameters.floor.memory);
    expect(p.iterations, LockParameters.floor.iterations);
  }, tags: 'timing');
}
