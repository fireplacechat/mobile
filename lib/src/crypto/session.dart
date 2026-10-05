// ignore_for_file: prefer_initializing_formals
import 'dart:collection';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:pqcrypto/pqcrypto.dart';

import 'package:fireplace/src/crypto/codec.dart';
import 'package:fireplace/src/crypto/device.dart';
import 'package:fireplace/src/crypto/key_checks.dart';
import 'package:fireplace/src/crypto/prekeys.dart';

class SessionException implements Exception {
  SessionException(this.message);
  final String message;
  @override
  String toString() => 'SessionException: $message';
}

/// Too many recent invalid messages needed expensive ratchet work; try again later.
/// Callers should retry the message later rather than discard it.
class SessionRateLimited extends SessionException {
  SessionRateLimited() : super('too many invalid messages, slowing down');
}

/// Every domain-separation string the protocol uses, in one place. Some keep an older
/// version number ON PURPOSE: changing a label changes every derived key, so a label
/// is only renamed in a release that also changes the keys (see
/// docs/decisions/0006 and test/crypto/labels_test.dart, which pins this table).
const protocolLabels = <String, String>{
  'handshake transcript': 'fireplace/v2/handshake',
  'root key': 'fireplace/v3/root',
  'ratchet step': 'fireplace/v3/ratchet',
  'message key': 'fireplace/v3/msg',
  'session id': 'fireplace/v4/sid',
  'message AAD': 'fireplace/v4/aad',
};

/// Wire protocol version. v1-v3 were development-only and are not accepted.
/// v3 = handshake v2 (prekeys) + hybrid double ratchet headers.
/// v4 = session id derived from the full handshake transcript and bound into the AAD.
const protocolVersion = 4;

Uint8List _bytes(dynamic v, {required int max, int? exact, String? what}) {
  if (v is! String) {
    throw FormatException('${what ?? 'field'} must be a string');
  }
  if (v.length > max * 2) throw FormatException('${what ?? 'field'} too long');
  final b = unb64(v);
  if (exact != null && b.length != exact) {
    throw FormatException('${what ?? 'field'} has wrong length');
  }
  if (b.length > max) throw FormatException('${what ?? 'field'} too long');
  return b;
}

/// Sent alongside the first message(s) so the recipient device can derive the same keys.
class HandshakeInit {
  HandshakeInit({
    required this.ek,
    required this.kemCt,
    required this.spkId,
    this.opkId,
    this.opkKemCt,
  });
  final Uint8List ek; // initiator's ephemeral X25519 public key
  final Uint8List
  kemCt; // ML-KEM-768 ciphertext for the signed prekey's KEM key
  final String spkId; // which signed prekey of the recipient was used
  final String? opkId; // which one-time prekey (if any)
  final Uint8List? opkKemCt; // ML-KEM-768 ciphertext for the one-time prekey

  Map<String, String> toJson() => {
    'ek': b64(ek),
    'kemCt': b64(kemCt),
    'spk': spkId,
    'opk': ?opkId,
    if (opkKemCt != null) 'opkCt': b64(opkKemCt!),
  };

  /// Throws [FormatException] for any malformed or inconsistent input.
  factory HandshakeInit.fromJson(Map<String, dynamic> j) {
    final spk = j['spk'], opk = j['opk'];
    if (spk is! String || spk.isEmpty || spk.length > 32) {
      throw const FormatException('bad spk id');
    }
    if (opk != null && (opk is! String || opk.isEmpty || opk.length > 32)) {
      throw const FormatException('bad opk id');
    }
    if ((opk == null) != (j['opkCt'] == null)) {
      throw const FormatException('inconsistent one-time prekey fields');
    }
    return HandshakeInit(
      ek: _bytes(j['ek'], max: 32, exact: 32, what: 'ek'),
      kemCt: _bytes(j['kemCt'], max: 1088, exact: 1088, what: 'kemCt'),
      spkId: spk,
      opkId: opk as String?,
      opkKemCt: j['opkCt'] == null
          ? null
          : _bytes(j['opkCt'], max: 1088, exact: 1088, what: 'opkCt'),
    );
  }
}

/// Wire format of one encrypted message for ONE recipient device.
///
/// Ratchet header: [rx]/[rk] are the sender's CURRENT ratchet public keys
/// (X25519 / ML-KEM-768), [rc] is the KEM ciphertext made to the receiver's
/// previous ratchet KEM key, [pn] the length of the sender's previous chain and
/// [n] this message's number in the current chain. They are sent with every
/// message so any message of a chain lets the receiver ratchet.
class Envelope {
  Envelope({
    required this.n,
    required this.pn,
    required this.sid,
    required this.rx,
    required this.rk,
    required this.rc,
    required this.nonce,
    required this.ct,
    required this.mac,
    this.handshake,
  });
  // 16,384 code points can occupy 98,304 bytes after JSON escaping, plus
  // the text payload wrapper. Keep receive allocation bounded while allowing
  // every permitted character (including emoji and escaped control characters).
  static const maxCiphertext = 128 * 1024;
  final int n;
  final int pn;
  final String sid; // session id (derived from the handshake)
  final Uint8List rx, rk, rc;
  final Uint8List nonce;
  final Uint8List ct;
  final Uint8List mac;
  final HandshakeInit? handshake;

  Map<String, dynamic> toJson() => {
    'pv': protocolVersion,
    'n': n,
    'pn': pn,
    'sid': sid,
    'rx': b64(rx),
    'rk': b64(rk),
    'rc': b64(rc),
    'nonce': b64(nonce),
    'ct': b64(ct),
    'mac': b64(mac),
    if (handshake != null) 'hs': handshake!.toJson(),
  };

  /// Validates the shape and sizes BEFORE any cryptographic work.
  /// Throws [FormatException] on anything unexpected.
  factory Envelope.fromJson(Map<String, dynamic> j) {
    if (j['pv'] != protocolVersion) {
      throw const FormatException('unsupported protocol version');
    }
    final n = j['n'], pn = j['pn'], sid = j['sid'];
    if (n is! int || n < 0 || n > 0x7fffffff) {
      throw const FormatException('bad counter');
    }
    if (pn is! int || pn < 0 || pn > 0x7fffffff) {
      throw const FormatException('bad previous-chain length');
    }
    if (sid is! String || sid.isEmpty || sid.length > 32) {
      throw const FormatException('bad session id');
    }
    final hs = j['hs'];
    if (hs != null && hs is! Map) throw const FormatException('bad handshake');
    return Envelope(
      n: n,
      pn: pn,
      sid: sid,
      rx: _bytes(j['rx'], max: 32, exact: 32, what: 'rx'),
      rk: _bytes(j['rk'], max: 1184, exact: 1184, what: 'rk'),
      rc: _bytes(j['rc'], max: 1088, exact: 1088, what: 'rc'),
      nonce: _bytes(j['nonce'], max: 12, exact: 12, what: 'nonce'),
      ct: _bytes(j['ct'], max: maxCiphertext, what: 'ct'),
      mac: _bytes(j['mac'], max: 16, exact: 16, what: 'mac'),
      handshake: hs == null
          ? null
          : HandshakeInit.fromJson(Map<String, dynamic>.from(hs)),
    );
  }
}

/// Mutable ratchet state. Operations run on a clone and are committed only
/// after the message authenticated, so a failed decrypt never changes anything.
class _State {
  _State({
    required this.rk,
    required this.dhsSeed,
    required this.dhsPub,
    required this.kemSecret,
    required this.kemPub,
  });

  Uint8List rk;
  Uint8List? cks, ckr;
  int ns = 0, nr = 0, pn = 0;
  Uint8List dhsSeed, dhsPub, kemSecret, kemPub; // my current ratchet keys
  Uint8List? dhrPub; // remote's current ratchet X25519 key
  Uint8List?
  pendingCt; // KEM ct to the peer's previous KEM key (sent in headers)
  final LinkedHashMap<String, Uint8List> skipped = LinkedHashMap();

  /// Ratchet public keys that can never legitimately start a new chain from the peer: the
  /// peer's retired keys and our own past keys (base64, oldest first, bounded). An honest
  /// peer's new chain always carries a fresh key, so a "new chain" under one of these is a
  /// replay or a reflection and is refused before any expensive work.
  final List<String> retired = [];
  static const maxRetired = 64;

  void retire(Uint8List key) {
    if (key.length != 32) return; // placeholder before the first real key
    final id = b64(key);
    if (retired.contains(id)) return;
    retired.add(id);
    while (retired.length > maxRetired) {
      retired.removeAt(0);
    }
  }

  bool cannotStartChain(Uint8List key) =>
      bytesEqual(key, dhsPub) || retired.contains(b64(key));

  _State clone() {
    final c =
        _State(
            rk: rk,
            dhsSeed: dhsSeed,
            dhsPub: dhsPub,
            kemSecret: kemSecret,
            kemPub: kemPub,
          )
          ..cks = cks
          ..ckr = ckr
          ..ns = ns
          ..nr = nr
          ..pn = pn
          ..dhrPub = dhrPub
          ..pendingCt = pendingCt;
    c.skipped.addAll(skipped);
    c.retired.addAll(retired);
    return c;
  }

  Map<String, dynamic> toJson() => {
    'rk': b64(rk),
    if (cks != null) 'cks': b64(cks!),
    if (ckr != null) 'ckr': b64(ckr!),
    'ns': ns,
    'nr': nr,
    'pn': pn,
    'dhsSeed': b64(dhsSeed),
    'dhsPub': b64(dhsPub),
    'kemSecret': b64(kemSecret),
    'kemPub': b64(kemPub),
    if (dhrPub != null) 'dhrPub': b64(dhrPub!),
    if (pendingCt != null) 'pendingCt': b64(pendingCt!),
    'skipped': skipped.map((k, v) => MapEntry(k, b64(v))),
    if (retired.isNotEmpty) 'retired': List<String>.of(retired),
  };

  /// Strict loader: throws [FormatException] on any wrong type, length, range
  /// or inconsistency between fields.
  factory _State.fromJson(Map<String, dynamic> j) {
    Uint8List key(String k, int len, {bool optional = false}) {
      final v = j[k];
      if (v == null && optional) return Uint8List(0);
      return _bytes(v, max: len, exact: len, what: k);
    }

    Uint8List? opt(String k, int len) => j[k] == null ? null : key(k, len);
    int counter(String k) {
      final v = j[k];
      if (v is! int || v < 0 || v > 0x7fffffff) {
        throw FormatException('bad $k');
      }
      return v;
    }

    final s =
        _State(
            rk: key('rk', 32),
            dhsSeed: key('dhsSeed', 32),
            dhsPub: key('dhsPub', 32),
            kemSecret: key('kemSecret', 2400),
            kemPub: key('kemPub', 1184),
          )
          ..cks = opt('cks', 32)
          ..ckr = opt('ckr', 32)
          ..ns = counter('ns')
          ..nr = counter('nr')
          ..pn = counter('pn')
          ..dhrPub = opt('dhrPub', 32)
          ..pendingCt = opt('pendingCt', 1088);
    if ((s.cks == null) != (s.pendingCt == null)) {
      throw const FormatException('inconsistent sending state');
    }
    if (s.ckr != null && s.dhrPub == null) {
      throw const FormatException('receiving chain without a remote key');
    }
    final skipped = j['skipped'];
    if (skipped is! Map || skipped.length > Session.maxSkip) {
      throw const FormatException('bad skipped keys');
    }
    final keyRe = RegExp(r'^[A-Za-z0-9+/]{43}=:\d{1,10}$');
    skipped.forEach((k, v) {
      if (k is! String || !keyRe.hasMatch(k)) {
        throw const FormatException('bad skipped key id');
      }
      s.skipped[k] = _bytes(v, max: 32, exact: 32, what: 'skipped key');
    });
    final retired = j['retired'] ?? const <Object?>[];
    if (retired is! List || retired.length > maxRetired) {
      throw const FormatException('bad retired keys');
    }
    for (final k in retired) {
      _bytes(k, max: 32, exact: 32, what: 'retired key');
      s.retired.add(k as String);
    }
    return s;
  }
}

/// A 1:1 session between one local device and one remote device.
///
/// **Handshake v2** (PQXDH-style: X25519 + ML-KEM-768 with signed and one-time prekeys):
///   DH1 = X25519(IK_a, SPK_b)   DH2 = X25519(EK_a, IK_b)
///   DH3 = X25519(EK_a, SPK_b)   DH4 = X25519(EK_a, OPK_b)          (if an OPK was claimed)
///   SS1 = ML-KEM-768 secret for SPK_b's KEM key, SS2 = same for OPK_b (if claimed)
///   RK0 = HKDF(lp(DH1, DH2, DH3, DH4, SS1, SS2), transcript)
/// The transcript commits to both account identities, all device/prekey public
/// keys, the ephemeral key and both KEM ciphertexts. The recipient's signed
/// prekey is certified by its account identity (Ed25519 + ML-DSA-65).
///
/// **Hybrid double ratchet** on top (Signal's Double Ratchet with an ML-KEM step
/// added to every DH step): the responder's signed prekey is its first ratchet
/// key. Each time a party replies it generates a fresh X25519 key and a fresh
/// ML-KEM key, DHs with the peer's newest X25519 key, encapsulates to the peer's
/// newest KEM key, and mixes both results into the root key:
///   (RK, CK) = HKDF(salt = RK, lp(DH, KEM secret)).
/// Message keys come from a symmetric hash chain and are deleted after use.
///
/// Properties: forward secrecy (handshake prekeys and per-message keys are
/// deleted); post-compromise security: after an attacker copies one side's
/// session state, the session heals once that side has answered a new chain
/// with key pairs generated after the copy (within about two round trips), as
/// long as either X25519 or ML-KEM-768 resists. Messages protected by keys
/// inside the copy stay readable to the attacker. Not covered: an attacker who
/// stays on the device.
class Session {
  Session._({
    required this.localUid,
    required this.localDevice,
    required this.remoteUid,
    required this.remoteDevice,
    required this.isInitiator,
    required this.sessionId,
    required this.createdAt,
    required _State state,
    HandshakeInit? handshake,
  }) : _st = state,
       _handshake = handshake;

  static const maxSkip = 1000;
  static final _x25519 = X25519();
  static final _aead = AesGcm.with256bits();
  static final _hmac = Hmac.sha256();

  final String localUid;
  final String localDevice;
  final String remoteUid;
  final String remoteDevice;
  final bool isInitiator;

  /// Identifies this session on the wire. Two devices that start sessions with
  /// each other at the same time end up with two sessions; both are kept and
  /// both sides send on the one with the smallest [sessionId].
  final String sessionId;

  /// When this device created/accepted the session (used to retire stale ones).
  final DateTime createdAt;

  _State _st;

  /// Recent failed attempts that needed expensive new-chain work (not persisted).
  final List<int> _failedChainAttempts = [];
  static const _maxFailedChainAttempts = 8;
  static const _failureWindowMs = 60 * 1000;

  HandshakeInit?
  _handshake; // attached to outgoing messages until the peer answers

  /// True iff the stored ratchet key pairs are internally consistent (public halves
  /// match their private halves). Call after loading from storage.
  Future<bool> selfCheck() async =>
      await KeyChecks.x25519Matches(_st.dhsSeed, _st.dhsPub) &&
      KeyChecks.mlKem768Matches(_st.kemSecret, _st.kemPub);

  /// True once the remote has successfully sent us a message (handshake acknowledged).
  bool get acknowledged => _handshake == null;
  bool get canSend => _st.cks != null;
  int get sendCounter => _st.ns;

  // ---------------------------------------------------------------- handshake

  static Future<void> _checkLocal(DeviceKeys local, DeviceBundle bundle) async {
    final kp = await _x25519.newKeyPairFromSeed(local.x25519Seed);
    final pub = (await kp.extractPublicKey()).bytes;
    if (!bytesEqual(pub, bundle.x25519Pub) ||
        !bytesEqual(local.kemPub, bundle.kemPub) ||
        bundle.deviceId != local.deviceId) {
      throw SessionException('local keys do not match the local device bundle');
    }
  }

  static SimplePublicKey _pk(List<int> b) =>
      SimplePublicKey(b, type: KeyPairType.x25519);

  static Future<(Session, HandshakeInit)> initiate({
    required DeviceKeys local,
    required DeviceBundle localBundle,
    required PreKeyBundle remote,
  }) async {
    await _checkLocal(local, localBundle);
    final dev = remote.device;
    if (!await dev.verifyCert()) {
      throw SessionException('remote device certificate invalid');
    }
    if (!await PreKeys.verifySigned(dev, remote.signed)) {
      throw SessionException('remote signed prekey invalid');
    }
    final spk = remote.signed;
    final opk = remote.oneTime;
    if (opk != null && opk.kind != PreKeyKind.oneTime) {
      throw SessionException('one-time prekey has the wrong kind');
    }

    final ek = await _x25519.newKeyPair();
    final ekPub = Uint8List.fromList((await ek.extractPublicKey()).bytes);
    final ik = await _x25519.newKeyPairFromSeed(local.x25519Seed);
    final dh1 = await _dh(ik, _pk(spk.x25519Pub));
    final dh2 = await _dh(ek, _pk(dev.x25519Pub));
    final dh3 = await _dh(ek, _pk(spk.x25519Pub));
    final dh4 = opk == null ? null : await _dh(ek, _pk(opk.x25519Pub));
    final (ct1, ss1) = PqcKem.kyber768.encapsulate(spk.kemPub);
    final (ct2, ss2) = opk == null
        ? (null, null)
        : PqcKem.kyber768.encapsulate(opk.kemPub);

    final hs = HandshakeInit(
      ek: ekPub,
      kemCt: ct1,
      spkId: spk.id,
      opkId: opk?.id,
      opkKemCt: ct2,
    );
    final (rk0, sid) = await _deriveRoot(
      initiator: localBundle,
      responder: dev,
      spk: (spk.id, spk.x25519Pub, spk.kemPub),
      opk: opk == null ? null : (opk.id, opk.x25519Pub, opk.kemPub),
      hs: hs,
      secrets: [dh1, dh2, dh3, dh4, ss1, ss2],
    );
    // First ratchet step: the responder's signed prekey is its first ratchet key.
    final st = _State(
      rk: rk0,
      dhsSeed: Uint8List(0),
      dhsPub: Uint8List(0),
      kemSecret: Uint8List(0),
      kemPub: Uint8List(0),
    );
    await _sendStep(st, spk.x25519Pub, spk.kemPub);
    final session = Session._(
      localUid: localBundle.uid,
      localDevice: localBundle.deviceId,
      remoteUid: dev.uid,
      remoteDevice: dev.deviceId,
      isInitiator: true,
      sessionId: sid,
      createdAt: DateTime.now(),
      state: st,
      handshake: hs,
    );
    return (session, hs);
  }

  /// [signedPreKey] / [oneTimePreKey] are the recipient's own prekey records
  /// named by the handshake; the caller looks them up and rejects unknown ids.
  static Future<Session> accept({
    required DeviceKeys local,
    required DeviceBundle localBundle,
    required DeviceBundle remote, // the initiating device
    required HandshakeInit handshake,
    required PreKeyRecord signedPreKey,
    PreKeyRecord? oneTimePreKey,
  }) async {
    await _checkLocal(local, localBundle);
    if (!await remote.verifyCert()) {
      throw SessionException('remote device certificate invalid');
    }
    if (handshake.spkId != signedPreKey.id) {
      throw SessionException('signed prekey id mismatch');
    }
    if ((handshake.opkId == null) != (oneTimePreKey == null) ||
        (oneTimePreKey != null && handshake.opkId != oneTimePreKey.id)) {
      throw SessionException('one-time prekey mismatch');
    }
    final ik = await _x25519.newKeyPairFromSeed(local.x25519Seed);
    final spk = await _x25519.newKeyPairFromSeed(signedPreKey.x25519Seed);
    final remoteIk = _pk(remote.x25519Pub);
    final ek = _pk(handshake.ek);
    final dh1 = await _dh(spk, remoteIk);
    final dh2 = await _dh(ik, ek);
    final dh3 = await _dh(spk, ek);
    Uint8List? dh4, ss2;
    if (oneTimePreKey != null) {
      final opk = await _x25519.newKeyPairFromSeed(oneTimePreKey.x25519Seed);
      dh4 = await _dh(opk, ek);
    }
    final Uint8List ss1;
    try {
      ss1 = PqcKem.kyber768.decapsulate(
        signedPreKey.kemSecret,
        handshake.kemCt,
      );
      if (oneTimePreKey != null) {
        ss2 = PqcKem.kyber768.decapsulate(
          oneTimePreKey.kemSecret,
          handshake.opkKemCt!,
        );
      }
    } catch (_) {
      throw SessionException('bad KEM ciphertext');
    }
    final (rk0, sid) = await _deriveRoot(
      initiator: remote,
      responder: localBundle,
      spk: (signedPreKey.id, signedPreKey.x25519Pub, signedPreKey.kemPub),
      opk: oneTimePreKey == null
          ? null
          : (oneTimePreKey.id, oneTimePreKey.x25519Pub, oneTimePreKey.kemPub),
      hs: handshake,
      secrets: [dh1, dh2, dh3, dh4, ss1, ss2],
    );
    // The signed prekey is this side's first ratchet key; the session keeps its
    // own copy so the prekey store can retire the original.
    final st = _State(
      rk: rk0,
      dhsSeed: Uint8List.fromList(signedPreKey.x25519Seed),
      dhsPub: Uint8List.fromList(signedPreKey.x25519Pub),
      kemSecret: Uint8List.fromList(signedPreKey.kemSecret),
      kemPub: Uint8List.fromList(signedPreKey.kemPub),
    );
    return Session._(
      localUid: localBundle.uid,
      localDevice: localBundle.deviceId,
      remoteUid: remote.uid,
      remoteDevice: remote.deviceId,
      isInitiator: false,
      sessionId: sid,
      createdAt: DateTime.now(),
      state: st,
    );
  }

  static Future<Uint8List> _dh(KeyPair kp, SimplePublicKey pk) async =>
      Uint8List.fromList(
        await (await _x25519.sharedSecretKey(
          keyPair: kp,
          remotePublicKey: pk,
        )).extractBytes(),
      );

  static Future<(Uint8List, String)> _deriveRoot({
    required DeviceBundle initiator,
    required DeviceBundle responder,
    required (String, Uint8List, Uint8List) spk,
    required (String, Uint8List, Uint8List)? opk,
    required HandshakeInit hs,
    required List<Uint8List?> secrets, // dh1..dh4, ss1, ss2 (null if absent)
  }) async {
    final transcript = lp([
      utf8Bytes(protocolLabels['handshake transcript']!),
      utf8Bytes(initiator.uid),
      utf8Bytes(initiator.deviceId),
      initiator.identityPub,
      initiator.x25519Pub,
      initiator.kemPub,
      utf8Bytes(responder.uid),
      utf8Bytes(responder.deviceId),
      responder.identityPub,
      responder.x25519Pub,
      responder.kemPub,
      utf8Bytes(spk.$1),
      spk.$2,
      spk.$3,
      utf8Bytes(opk?.$1 ?? ''),
      opk?.$2 ?? const <int>[],
      opk?.$3 ?? const <int>[],
      hs.ek,
      hs.kemCt,
      hs.opkKemCt ?? const <int>[],
    ]);
    // Absent components are length-prefixed empties, so the layout is unambiguous.
    final ikm = lp([for (final s in secrets) s ?? const <int>[]]);
    final root = await Hkdf(hmac: _hmac, outputLength: 32).deriveKey(
      secretKey: SecretKey(ikm),
      nonce: const <int>[],
      info: concat([utf8Bytes(protocolLabels['root key']!), transcript]),
    );
    // The session id commits to EVERYTHING the root key does (participants, identities,
    // all keys, prekey ids, every ciphertext), so two handshakes that derive different
    // roots can never share an id. 128 bits, url-safe, no padding.
    final h = (await Sha256().hash(
      lp([utf8Bytes(protocolLabels['session id']!), transcript]),
    )).bytes;
    final sid = b64(h.sublist(0, 16))
        .replaceAll('+', '-')
        .replaceAll('/', '_')
        .replaceAll('=', '');
    return (Uint8List.fromList(await root.extractBytes()), sid);
  }

  // ------------------------------------------------------------------ ratchet

  /// (RK, CK) = HKDF(salt = RK, lp(DH, KEM secret)).
  static Future<(Uint8List, Uint8List)> _kdfRk(
    Uint8List rk,
    Uint8List dh,
    Uint8List ss,
  ) async {
    final out = await Hkdf(hmac: _hmac, outputLength: 64).deriveKey(
      secretKey: SecretKey(lp([dh, ss])),
      nonce: rk,
      info: utf8Bytes(protocolLabels['ratchet step']!),
    );
    final b = Uint8List.fromList(await out.extractBytes());
    return (
      Uint8List.fromList(b.sublist(0, 32)),
      Uint8List.fromList(b.sublist(32, 64)),
    );
  }

  /// Sending half of a ratchet step: fresh key pairs, DH + KEM towards the
  /// peer's newest keys, new sending chain.
  static Future<void> _sendStep(
    _State st,
    Uint8List remoteX,
    Uint8List remoteKem,
  ) async {
    final seed = randomBytes(32);
    final kp = await _x25519.newKeyPairFromSeed(seed);
    final pub = Uint8List.fromList((await kp.extractPublicKey()).bytes);
    final (kemPk, kemSk) = PqcKem.kyber768.generateKeyPair();
    final dh = await _dh(kp, _pk(remoteX));
    final (ct, ss) = PqcKem.kyber768.encapsulate(remoteKem);
    final (rk, ck) = await _kdfRk(st.rk, dh, ss);
    st.pn = st.ns;
    st.ns = 0;
    st.rk = rk;
    st.cks = ck;
    st.retire(st.dhsPub);
    st.dhsSeed = seed;
    st.dhsPub = pub;
    st.kemPub = kemPk;
    st.kemSecret = kemSk;
    st.pendingCt = ct;
  }

  /// Receiving half: the peer used our current keys; derive the receiving
  /// chain, then immediately take our own sending step.
  static Future<void> _recvStep(
    _State st,
    Uint8List rx,
    Uint8List peerKem,
    Uint8List rc,
  ) async {
    final mine = await _x25519.newKeyPairFromSeed(st.dhsSeed);
    final dh = await _dh(mine, _pk(rx));
    final Uint8List ss;
    try {
      ss = PqcKem.kyber768.decapsulate(st.kemSecret, rc);
    } catch (_) {
      throw SessionException('bad ratchet KEM ciphertext');
    }
    final (rk, ck) = await _kdfRk(st.rk, dh, ss);
    st.rk = rk;
    st.ckr = ck;
    st.nr = 0;
    if (st.dhrPub != null) st.retire(st.dhrPub!);
    st.dhrPub = rx;
    await _sendStep(st, rx, peerKem);
  }

  static Future<Uint8List> _step(Uint8List ck, int tag) async =>
      Uint8List.fromList(
        (await _hmac.calculateMac([tag], secretKey: SecretKey(ck))).bytes,
      );

  static Future<SecretKey> _msgKey(Uint8List mk) =>
      Hkdf(hmac: _hmac, outputLength: 32).deriveKey(
        secretKey: SecretKey(mk),
        nonce: const <int>[],
        info: utf8Bytes(protocolLabels['message key']!),
      );

  /// Stores message keys of the current receiving chain up to (excluding) [until].
  static Future<void> _skipTo(_State st, Uint8List chainPub, int until) async {
    if (st.ckr == null || until <= st.nr) return;
    if (until - st.nr > maxSkip) {
      throw SessionException('too many skipped messages');
    }
    while (st.nr < until) {
      st.skipped['${b64(chainPub)}:${st.nr}'] = await _step(st.ckr!, 1);
      st.ckr = await _step(st.ckr!, 2);
      st.nr++;
    }
    while (st.skipped.length > maxSkip) {
      st.skipped.remove(st.skipped.keys.first);
    }
  }

  static Future<Uint8List> _aad(
    String sid,
    String chatId,
    String sUid,
    String sDev,
    String rUid,
    String rDev,
    int n,
    int pn,
    Uint8List rx,
    Uint8List rk,
    Uint8List rc,
  ) async {
    final headerHash = (await Sha256().hash(lp([rk, rc]))).bytes;
    return lp([
      utf8Bytes(protocolLabels['message AAD']!),
      utf8Bytes(sid),
      utf8Bytes(chatId),
      utf8Bytes(sUid),
      utf8Bytes(sDev),
      utf8Bytes(rUid),
      utf8Bytes(rDev),
      u64(n),
      u64(pn),
      rx,
      headerHash,
    ]);
  }

  Future<Envelope> encrypt(
    List<int> plaintext, {
    required String chatId,
  }) async {
    final st = _st;
    if (st.cks == null) {
      throw SessionException('this session cannot send yet');
    }
    final n = st.ns;
    final mk = await _step(st.cks!, 1);
    final next = await _step(st.cks!, 2);
    final rx = st.dhsPub, rk = st.kemPub, rc = st.pendingCt!;
    final box = await _aead.encrypt(
      plaintext,
      secretKey: await _msgKey(mk),
      aad: await _aad(
        sessionId,
        chatId,
        localUid,
        localDevice,
        remoteUid,
        remoteDevice,
        n,
        st.pn,
        rx,
        rk,
        rc,
      ),
    );
    st.cks = next;
    st.ns = n + 1;
    return Envelope(
      n: n,
      pn: st.pn,
      sid: sessionId,
      rx: rx,
      rk: rk,
      rc: rc,
      nonce: Uint8List.fromList(box.nonce),
      ct: Uint8List.fromList(box.cipherText),
      mac: Uint8List.fromList(box.mac.bytes),
      handshake: _handshake,
    );
  }

  /// Decrypts [env]. State only changes if authentication succeeds.
  /// Replays and already-consumed counters fail.
  Future<Uint8List> decrypt(Envelope env, {required String chatId}) async {
    if (env.sid != sessionId) throw SessionException('wrong session');
    var newChainWork = false;
    try {
      return await _decrypt(env, chatId, () => newChainWork = true);
    } on SessionRateLimited {
      rethrow;
    } on SessionException {
      // Starting a new chain costs an X25519 + an ML-KEM decapsulation before the
      // tag can be checked; remember failures so a peer cannot make us redo it forever.
      if (newChainWork) {
        _failedChainAttempts.add(DateTime.now().millisecondsSinceEpoch);
      }
      rethrow;
    }
  }

  Future<Uint8List> _decrypt(
    Envelope env,
    String chatId,
    void Function() markNewChain,
  ) async {
    final st = _st.clone();
    final SecretKey key;
    final skippedId = '${b64(env.rx)}:${env.n}';
    final stored = st.skipped.remove(skippedId);
    try {
      if (stored != null) {
        key = await _msgKey(stored);
      } else {
        final sameChain = st.dhrPub != null && bytesEqual(st.dhrPub!, env.rx);
        if (!sameChain) {
          // Cheap structural rejections first: they cost nothing, so they must neither
          // count towards the failure budget nor be blocked by it.
          if (st.cannotStartChain(env.rx)) {
            throw SessionException('replayed or reflected chain');
          }
          if (env.n > maxSkip) {
            throw SessionException('too many skipped messages');
          }
          if (st.ckr != null && env.pn - st.nr > maxSkip) {
            throw SessionException('too many skipped messages');
          }
          final now = DateTime.now().millisecondsSinceEpoch;
          _failedChainAttempts.removeWhere((t) => now - t > _failureWindowMs);
          if (_failedChainAttempts.length >= _maxFailedChainAttempts) {
            throw SessionRateLimited();
          }
          if (st.ckr != null) await _skipTo(st, st.dhrPub!, env.pn);
          markNewChain(); // from here on the attempt costs X25519 + ML-KEM work
          await _recvStep(st, env.rx, env.rk, env.rc);
        } else if (env.n < st.nr) {
          throw SessionException('replayed or unknown counter');
        }
        await _skipTo(st, env.rx, env.n);
        if (st.ckr == null) throw SessionException('no receiving chain');
        final mk = await _step(st.ckr!, 1);
        st.ckr = await _step(st.ckr!, 2);
        st.nr = env.n + 1;
        key = await _msgKey(mk);
      }
    } on SessionException {
      rethrow;
    } catch (_) {
      throw SessionException('malformed ratchet header');
    }

    final List<int> plain;
    try {
      plain = await _aead.decrypt(
        SecretBox(env.ct, nonce: env.nonce, mac: Mac(env.mac)),
        secretKey: key,
        aad: await _aad(
          sessionId,
          chatId,
          remoteUid,
          remoteDevice,
          localUid,
          localDevice,
          env.n,
          env.pn,
          env.rx,
          env.rk,
          env.rc,
        ),
      );
    } on SecretBoxAuthenticationError {
      throw SessionException('authentication failed');
    }
    _st = st; // commit
    _handshake = null; // peer proved it holds the session keys
    return Uint8List.fromList(plain);
  }

  // -------------------------------------------------------------- persistence

  Map<String, dynamic> toJson() => {
    'pv': protocolVersion,
    'localUid': localUid,
    'localDevice': localDevice,
    'remoteUid': remoteUid,
    'remoteDevice': remoteDevice,
    'isInitiator': isInitiator,
    'sid': sessionId,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'st': _st.toJson(),
    if (_handshake != null) 'hs': _handshake!.toJson(),
  };

  /// Returns null for sessions from an older protocol version AND for stored
  /// state that fails validation (corrupt, truncated, tampered). The caller
  /// then starts a fresh handshake instead of crashing.
  static Session? tryFromJson(Map<String, dynamic> j) {
    if (j['pv'] != protocolVersion) return null;
    try {
      return Session.fromJson(j);
    } catch (_) {
      return null;
    }
  }

  /// Strict: throws [FormatException] unless every field has the right type,
  /// length and range and the ratchet fields are consistent with each other.
  factory Session.fromJson(Map<String, dynamic> j) {
    String str(String k, {int max = 128}) {
      final v = j[k];
      if (v is! String || v.isEmpty || v.length > max) {
        throw FormatException('bad $k');
      }
      return v;
    }

    final created = j['createdAt'];
    if (created is! int || created < 0 || created > 8640000000000000) {
      throw const FormatException('bad createdAt');
    }
    if (j['isInitiator'] is! bool) throw const FormatException('bad role');
    final stJson = j['st'];
    if (stJson is! Map) throw const FormatException('bad state');
    final hs = j['hs'];
    if (hs != null && hs is! Map) throw const FormatException('bad handshake');
    final st = _State.fromJson(Map<String, dynamic>.from(stJson));
    final isInit = j['isInitiator'] as bool;
    // An initiator always has a sending chain; a responder gets both chains together.
    if (isInit && st.cks == null) {
      throw const FormatException('initiator without chain');
    }
    if (hs != null && !isInit) {
      throw const FormatException('responder with handshake');
    }
    return Session._(
      localUid: str('localUid'),
      localDevice: str('localDevice'),
      remoteUid: str('remoteUid'),
      remoteDevice: str('remoteDevice'),
      isInitiator: isInit,
      sessionId: str('sid', max: 32),
      createdAt: DateTime.fromMillisecondsSinceEpoch(created),
      state: st,
      handshake: hs == null
          ? null
          : HandshakeInit.fromJson(Map<String, dynamic>.from(hs)),
    );
  }
}
