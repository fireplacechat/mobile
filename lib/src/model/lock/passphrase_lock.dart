import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:cryptography/cryptography.dart';

import 'package:fireplace/src/crypto/codec.dart';
import 'package:fireplace/src/db/wrapping_secret_store.dart';

/// How long the app may be away before it locks itself (decision 0033).
enum AutoLock {
  immediately(Duration.zero, 'Immediately'),
  oneMinute(Duration(minutes: 1), 'After 1 minute'),
  fiveMinutes(Duration(minutes: 5), 'After 5 minutes'),
  oneHour(Duration(hours: 1), 'After 1 hour'),
  oneDay(Duration(days: 1), 'After 1 day');

  const AutoLock(this.after, this.label);
  final Duration after;
  final String label;

  static const standard = fiveMinutes;

  static AutoLock fromSeconds(Object? seconds) => values.firstWhere(
    (a) => a.after.inSeconds == seconds,
    orElse: () => standard,
  );
}

/// Turning the lock on or off, if stopped half-way.
enum LockChange { on, off }

/// Argon2id cost, measured once on the phone where the passphrase is set.
class LockParameters {
  const LockParameters({required this.memory, required this.iterations});

  /// In 1 KiB blocks, as `cryptography` counts them.
  final int memory;
  final int iterations;

  /// OWASP's minimum for Argon2id: 19 MiB and 2 passes.
  static const floor = LockParameters(memory: 19 * 1024, iterations: 2);
  static const maxMemory = 64 * 1024;
  static const maxIterations = 8;
}

/// What is stored, readable, in `passlock:{uid}`: nothing that opens data
/// without the passphrase and the device secret.
class LockRecord {
  const LockRecord({
    required this.salt,
    required this.parameters,
    required this.sealedKey,
    required this.deviceId,
    required this.autoLock,
    required this.previewsWereOn,
    this.pending,
  });

  final List<int> salt;
  final LockParameters parameters;

  /// The data key, sealed with the key derived from the passphrase.
  final String sealedKey;
  final String deviceId;
  final AutoLock autoLock;

  /// Whether notification previews were on before the lock forced them off.
  final bool previewsWereOn;
  final LockChange? pending;

  LockRecord copyWith({
    List<int>? salt,
    LockParameters? parameters,
    String? sealedKey,
    AutoLock? autoLock,
  }) => LockRecord(
    salt: salt ?? this.salt,
    parameters: parameters ?? this.parameters,
    sealedKey: sealedKey ?? this.sealedKey,
    deviceId: deviceId,
    autoLock: autoLock ?? this.autoLock,
    previewsWereOn: previewsWereOn,
    pending: pending,
  );

  LockRecord withPending(LockChange? change) => LockRecord(
    salt: salt,
    parameters: parameters,
    sealedKey: sealedKey,
    deviceId: deviceId,
    autoLock: autoLock,
    previewsWereOn: previewsWereOn,
    pending: change,
  );

  Map<String, Object?> toJson() => {
    'v': 1,
    'salt': b64(salt),
    'memory': parameters.memory,
    'iterations': parameters.iterations,
    'key': sealedKey,
    'device': deviceId,
    'autoLock': autoLock.after.inSeconds,
    'previews': previewsWereOn,
    if (pending != null) 'pending': pending!.name,
  };

  static LockRecord fromJson(Map<String, dynamic> j) {
    if (j['v'] != 1) throw const FormatException('Unknown lock record.');
    return LockRecord(
      salt: unb64(j['salt'] as String),
      parameters: LockParameters(
        memory: j['memory'] as int,
        iterations: j['iterations'] as int,
      ),
      sealedKey: j['key'] as String,
      deviceId: j['device'] as String,
      autoLock: AutoLock.fromSeconds(j['autoLock']),
      previewsWereOn: j['previews'] == true,
      pending: switch (j['pending']) {
        'on' => LockChange.on,
        'off' => LockChange.off,
        _ => null,
      },
    );
  }
}

/// Derives the key that seals the data key: Argon2id of the passphrase, then
/// HMAC-SHA256 with the device secret (decision 0033).
typedef DeriveLockKey = Future<List<int>> Function(
  String passphrase,
  List<int> salt,
  LockParameters parameters,
  List<int> deviceSecret,
);

Argon2id _argon2(LockParameters p) => Argon2id(
  parallelism: 1,
  memory: p.memory,
  iterations: p.iterations,
  hashLength: 32,
);

/// [DeriveLockKey] on a background isolate: it takes about a second.
Future<List<int>> deriveLockKey(
  String passphrase,
  List<int> salt,
  LockParameters parameters,
  List<int> deviceSecret,
) => Isolate.run(() async {
  final hash = await _argon2(parameters)
      .deriveKey(secretKey: SecretKey(utf8.encode(passphrase)), nonce: salt);
  final mac = await Hmac.sha256().calculateMac(
    await hash.extractBytes(),
    secretKey: SecretKey(deviceSecret),
  );
  return mac.bytes;
});

/// Measures this phone, on a background isolate: from [LockParameters.floor],
/// doubles the memory while a run takes under [memoryTarget], then adds
/// passes while it takes under [target].
Future<LockParameters> calibrateLock({
  Duration memoryTarget = const Duration(milliseconds: 400),
  Duration target = const Duration(seconds: 1),
}) => Isolate.run(() async {
  Future<Duration> time(LockParameters p) async {
    final watch = Stopwatch()..start();
    await _argon2(p).deriveKey(
      secretKey: SecretKey(utf8.encode('calibration')),
      nonce: List.filled(16, 0),
    );
    return watch.elapsed;
  }

  var p = LockParameters.floor;
  while (p.memory * 2 <= LockParameters.maxMemory &&
      await time(p) < memoryTarget) {
    p = LockParameters(memory: p.memory * 2, iterations: p.iterations);
  }
  while (p.iterations < LockParameters.maxIterations &&
      await time(p) < target) {
    p = LockParameters(memory: p.memory, iterations: p.iterations + 1);
  }
  return p;
});

/// Runs [work] with the account's stores to itself: the account lock, so
/// another isolate does not write a session while items are rewritten.
typedef Exclusive = Future<void> Function(Future<void> Function() work);

/// The optional passphrase lock for one device's accounts (decision 0033).
/// Holds no state of its own: the data key is in [WrappingSecretStore] while
/// unlocked, and everything else is in `passlock:{uid}`.
class PassphraseLock {
  PassphraseLock(
    this._store, {
    this.derive = deriveLockKey,
    Future<LockParameters> Function()? calibrate,
  }) : _calibrate = calibrate ?? calibrateLock;

  final WrappingSecretStore _store;
  final DeriveLockKey derive;
  final Future<LockParameters> Function() _calibrate;

  static String recordKey(String uid) => 'passlock:$uid';
  static String secretKey(String uid) => 'passlockpepper:$uid';
  static String _noPreview(String uid) => 'pushnopreview:$uid';
  static String _label(String uid) => 'fireplace/v1/passlock:$uid';

  /// The shortest passphrase accepted.
  static const minimumLength = 8;

  Future<LockRecord?> record(String uid) async {
    final raw = await _store.read(recordKey(uid));
    if (raw == null) return null;
    return LockRecord.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> _save(String uid, LockRecord r) =>
      _store.write(recordKey(uid), jsonEncode(r.toJson()));

  Future<List<int>> _deviceSecret(String uid) async {
    final raw = await _store.read(secretKey(uid));
    // Without it the passphrase opens nothing: the data is as good as gone.
    if (raw == null) throw StateError('The lock secret is missing.');
    return unb64(raw);
  }

  /// Whether this account's data is held open now.
  bool isOpen(String uid) => _store.openAccount == uid;

  /// Opens the data key with [passphrase]. False, changing nothing, when it
  /// is not the passphrase. A change left half-way is not finished here; see
  /// [finishPending].
  Future<bool> unlock(String uid, String passphrase) async {
    final r = await record(uid);
    if (r == null) throw StateError('The passphrase lock is off.');
    final key = await derive(
      passphrase,
      r.salt,
      r.parameters,
      await _deviceSecret(uid),
    );
    final List<int> dataKey;
    try {
      dataKey = await WrappingSecretStore.unseal(key, r.sealedKey, _label(uid));
    } on SecretBoxAuthenticationError {
      return false;
    }
    _store.open(
      uid: uid,
      deviceId: r.deviceId,
      dataKey: dataKey,
      wrapWrites: r.pending != LockChange.off,
    );
    return true;
  }

  /// Turns the lock on for [uid] on [deviceId]: wraps the data that opens
  /// messages, and turns notification previews off (decision 0033).
  Future<void> enable({
    required String uid,
    required String deviceId,
    required String passphrase,
    required Exclusive exclusive,
  }) async {
    if (passphrase.length < minimumLength) {
      throw ArgumentError('The passphrase is too short.');
    }
    if (await record(uid) != null) throw StateError('Already on.');
    final parameters = await _calibrate();
    final salt = randomBytes(16), secret = randomBytes(32);
    final dataKey = randomBytes(32);
    final key = await derive(passphrase, salt, parameters, secret);
    final previews = await _store.read(_noPreview(uid)) == null;
    await _store.write(secretKey(uid), b64(secret));
    await _save(
      uid,
      LockRecord(
        salt: salt,
        parameters: parameters,
        sealedKey: await WrappingSecretStore.seal(key, dataKey, _label(uid)),
        deviceId: deviceId,
        autoLock: AutoLock.standard,
        previewsWereOn: previews,
        pending: LockChange.on,
      ),
    );
    // Before anything is wrapped: the background handlers then stop opening
    // the stores.
    await _store.write(_noPreview(uid), '1');
    _store.open(
      uid: uid,
      deviceId: deviceId,
      dataKey: dataKey,
      wrapWrites: true,
    );
    await finishPending(uid, exclusive: exclusive);
  }

  /// Finishes turning the lock on or off, if that was stopped half-way.
  /// Needs the data key.
  Future<void> finishPending(String uid, {required Exclusive exclusive}) async {
    final r = await record(uid);
    final change = r?.pending;
    if (r == null || change == null) return;
    if (!isOpen(uid)) throw const SecretsLocked();
    final wrap = change == LockChange.on;
    await exclusive(() async {
      for (final name in await _store.coveredItems()) {
        await _store.rewrite(name, wrapped: wrap);
      }
    });
    if (wrap) {
      await _save(uid, r.withPending(null));
      return;
    }
    await _store.delete(recordKey(uid));
    await _store.delete(secretKey(uid));
    if (r.previewsWereOn) await _store.delete(_noPreview(uid));
    _store.close();
  }

  /// Turns the lock off: the data goes back to the secure store alone, and
  /// previews to what they were. Needs the data key.
  Future<void> disable(String uid, {required Exclusive exclusive}) async {
    final r = await record(uid);
    if (r == null) return;
    if (!isOpen(uid)) throw const SecretsLocked();
    await _save(uid, r.withPending(LockChange.off));
    _store.stopWrapping();
    await finishPending(uid, exclusive: exclusive);
  }

  /// A new passphrase for the same data key. False, changing nothing, when
  /// [current] is not the passphrase.
  Future<bool> change(String uid, String current, String next) async {
    if (next.length < minimumLength) {
      throw ArgumentError('The passphrase is too short.');
    }
    final r = await record(uid);
    if (r == null) throw StateError('The passphrase lock is off.');
    final secret = await _deviceSecret(uid);
    final List<int> dataKey;
    try {
      dataKey = await WrappingSecretStore.unseal(
        await derive(current, r.salt, r.parameters, secret),
        r.sealedKey,
        _label(uid),
      );
    } on SecretBoxAuthenticationError {
      return false;
    }
    final parameters = await _calibrate();
    final salt = randomBytes(16);
    final key = await derive(next, salt, parameters, secret);
    // One write: stopped before it, the old passphrase still opens.
    await _save(
      uid,
      r.copyWith(
        salt: salt,
        parameters: parameters,
        sealedKey: await WrappingSecretStore.seal(key, dataKey, _label(uid)),
      ),
    );
    return true;
  }

  /// Whether [passphrase] is this account's, without changing anything.
  Future<bool> verify(String uid, String passphrase) async {
    final r = await record(uid);
    if (r == null) return false;
    try {
      await WrappingSecretStore.unseal(
        await derive(
          passphrase,
          r.salt,
          r.parameters,
          await _deviceSecret(uid),
        ),
        r.sealedKey,
        _label(uid),
      );
      return true;
    } on SecretBoxAuthenticationError {
      return false;
    }
  }

  Future<void> setAutoLock(String uid, AutoLock autoLock) async {
    final r = await record(uid);
    if (r != null) await _save(uid, r.copyWith(autoLock: autoLock));
  }

  /// Forgets the data key. The account's session must be closed first.
  void lock() => _store.close();
}
