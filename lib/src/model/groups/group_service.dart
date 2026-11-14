import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:fireplace/src/crypto/codec.dart';
import 'package:fireplace/src/crypto/group_crypto.dart';
import 'package:fireplace/src/db/group_record_file.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/db/secret_store.dart';
import 'package:fireplace/src/model/chat/message_payload.dart';
import 'package:fireplace/src/model/chat/send_allowance.dart';
import 'package:fireplace/src/model/groups/group_models.dart';
import 'package:fireplace/src/model/groups/group_requests.dart';
import 'package:fireplace/src/model/keys/key_service.dart';

/// Group chats for one account on this device (mobile decision 0050,
/// `docs/protocol/group-chats-v1.md`, backend decision 0023).
///
/// All MLS work runs one call at a time. Each change from the core is checked,
/// saved (MLS records and this service's cursors together, atomically) and
/// only then accepted, so a crash loses nothing and repeats nothing.
///
/// Commits are applied strictly in epoch order. A Commit is checked against
/// the group's rules before it is kept: a rename or role change only from an
/// administrator; a self-update adds and removes nobody; members are added
/// only by administrators (or an account adding its own device), and removed
/// only by administrators or once the server has fenced them.
class GroupService {
  GroupService({
    required FirebaseFirestore db,
    required this.uid,
    required this._device,
    required this._secrets,
    required this._historyDir,
    required this._messages,
    SendAllowance? allowance,
    Duration? requestTimeout,
    DateTime Function()? clock,
  }) : _db = db,
       _allowance = allowance ?? SendAllowance(),
       _now = clock ?? DateTime.now,
       _requests = GroupRequests(db, uid, timeout: requestTimeout);

  final FirebaseFirestore _db;
  final String uid;
  final LocalDevice _device;
  final SecretStore _secrets;
  final Directory _historyDir;
  final LocalMessageStore _messages;
  final SendAllowance _allowance;
  final DateTime Function() _now;
  final GroupRequests _requests;

  late GroupRecordFile _file;
  late GroupCrypto _crypto;
  Future<void> _tail = Future<void>.value();
  bool _closed = false;

  final _groups = <String, GroupInfo>{};
  final _groupsCtrl = StreamController<Map<String, GroupInfo>>.broadcast();
  var _invitations = <GroupInvitation>[];
  final _invitesCtrl = StreamController<List<GroupInvitation>>.broadcast();
  final _colors = <String, MemberColors>{};
  final _colorsCtrl = StreamController<String>.broadcast();
  final _subs = <StreamSubscription<Object?>>[];
  final _groupSubs = <String, List<StreamSubscription<Object?>>>{};
  final _rosters = <String, Map<String, dynamic>>{};
  // Events that arrived ahead of this device's epoch, waiting for Commits.
  final _waiting =
      <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
  final _pending = <String>{}; // groups with an own Commit awaiting its slot

  String get deviceId => _device.keys.deviceId;

  /// The groups this device is in, as MLS authenticated them.
  Map<String, GroupInfo> get groups => Map.unmodifiable(_groups);
  Stream<Map<String, GroupInfo>> watchGroups() async* {
    yield groups;
    yield* _groupsCtrl.stream;
  }

  List<GroupInvitation> get invitations => _invitations;
  Stream<List<GroupInvitation>> watchInvitations() async* {
    yield _invitations;
    yield* _invitesCtrl.stream;
  }

  MemberColors colorsOf(String gid) =>
      Map.unmodifiable(_colors[gid] ?? const {});
  Stream<String> get colorChanges => _colorsCtrl.stream;

  // ---------------------------------------------------------------- start

  Future<void> start() async {
    _file = await GroupRecordFile.open(
      historyDir: _historyDir,
      secrets: _secrets,
      uid: uid,
    );
    _crypto = GroupCrypto.open(_file.blob());
    if (_file.isEmpty) {
      final hash = await Sha256().hash(_device.bundle.cert);
      await _change({
        'op': 'device',
        'identity': jsonEncode(_device.identity.toJson()),
        'uid': uid,
        'device': deviceId,
        'deviceCertHash': b64(hash.bytes),
        'generation': 1,
      });
    }
    await _loadColors();
    for (final gid
        in (_crypto.call({'op': 'groups'})['groups'] as List).cast<String>()) {
      final info = _info(gid);
      if (info != null && info.active) _groups[gid] = info;
      // An own Commit saved before a restart still waits for its epoch's slot.
      try {
        if (_crypto.call({'op': 'info', 'gid': gid})['pending'] == true) {
          _pending.add(gid);
        }
      } on GroupCryptoException {
        // Unknown group.
      }
    }
    _emitGroups();
    await _replenishPackages();
    _subs.add(
      _db
          .collection('users/$uid/groupRefs')
          .snapshots()
          .listen((s) => _serial(() => _onRefs(s)), onError: (_) {}),
    );
    _subs.add(
      _db.collection('users/$uid/groupInvites').snapshots().listen((s) {
        _invitations = [
          for (final d in s.docs)
            GroupInvitation(
              gid: d.id,
              inviter: '${d.data()['by']}',
              at: (d.data()['at'] as Timestamp?)?.toDate() ?? _now(),
            ),
        ];
        _invitesCtrl.add(_invitations);
      }, onError: (_) {}),
    );
  }

  Future<void> close() async {
    _closed = true;
    for (final s in [..._subs, for (final l in _groupSubs.values) ...l]) {
      await s.cancel();
    }
    await _tail.catchError((Object _) {});
    _crypto.close();
    await _groupsCtrl.close();
    await _invitesCtrl.close();
    await _colorsCtrl.close();
  }

  // ---------------------------------------------------------------- the core

  /// Runs [f] after every earlier MLS call has finished.
  Future<T> _serial<T>(Future<T> Function() f) {
    final run = _tail.then((_) => f());
    _tail = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  /// One changing core call: [check] may refuse the result (then nothing is
  /// kept); otherwise the changes and [extra] app records are saved, then the
  /// core accepts.
  Future<Map<String, dynamic>> _change(
    Map<String, dynamic> request, {
    bool Function(Map<String, dynamic> result)? check,
    Map<String, List<int>?> extra = const {},
    Future<void> Function(Map<String, dynamic> result)? beforeSave,
  }) async {
    final result = _crypto.call(request);
    try {
      if (check != null && !check(result)) {
        throw GroupCryptoException(2);
      }
      await beforeSave?.call(result);
      _file.apply(result['changes']);
      _file.setApp(extra);
      await _file.save();
    } catch (_) {
      _crypto.rollback();
      _file = await GroupRecordFile.open(
        historyDir: _historyDir,
        secrets: _secrets,
        uid: uid,
      );
      rethrow;
    }
    _crypto.accept();
    return result;
  }

  GroupInfo? _info(String gid) {
    try {
      return GroupInfo.fromCore(_crypto.call({'op': 'info', 'gid': gid}));
    } on GroupCryptoException {
      return null;
    }
  }

  void _emitGroups() {
    if (!_groupsCtrl.isClosed) _groupsCtrl.add(groups);
  }

  /// Keeps ten key packages published, so admins can add this device.
  Future<void> _replenishPackages() => _serial(() async {
    final col = _db.collection('users/$uid/devices/$deviceId/mlsPackages');
    final have = {for (final d in (await col.get()).docs) d.id};
    final missing = [
      for (var i = 0; i < GroupLimits.keyPackagesPerDevice; i++)
        if (!have.contains('$i')) '$i',
    ];
    if (missing.isEmpty) return;
    final result = await _change({
      'op': 'key_packages',
      'count': missing.length,
    });
    final batch = _db.batch();
    final packages = (result['packages'] as List).cast<Map>();
    for (var i = 0; i < missing.length; i++) {
      batch.set(col.doc(missing[i]), {
        'kp': Blob(unb64(packages[i]['keyPackage'] as String)),
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  });

  // ---------------------------------------------------------------- groups

  Future<void> _onRefs(QuerySnapshot<Map<String, dynamic>> refs) async {
    final listed = {for (final d in refs.docs) d.id: d.data()};
    for (final entry in listed.entries) {
      final gid = entry.key;
      if (!_groups.containsKey(gid)) {
        await _joinFromWelcome(
          gid,
          (entry.value['joinedEpoch'] as num?)?.toInt() ?? 0,
        );
      }
      if (_groups.containsKey(gid) && !_groupSubs.containsKey(gid)) _watch(gid);
    }
    // Removed by the server (left, removed, fenced): stop and forget the
    // group's keys. Its history stays on this device.
    for (final gid in [..._groups.keys]) {
      if (!listed.containsKey(gid)) await _drop(gid);
    }
  }

  Future<void> _joinFromWelcome(String gid, int joinedEpoch) async {
    final welcomes = await _db
        .collection('groups/$gid/welcomes')
        .where('uid', isEqualTo: uid)
        .get();
    for (final w in welcomes.docs) {
      if (((w.data()['epoch'] as num?)?.toInt() ?? 0) < joinedEpoch) continue;
      final ct = w.data()['ct'];
      if (ct is! Blob) continue;
      try {
        // A Welcome for another of this account's devices is refused; try the next.
        final result = await _change({'op': 'join', 'welcome': b64(ct.bytes)});
        final info = GroupInfo.fromCore(result);
        if (info.gid != gid) continue;
        _groups[gid] = info;
        _emitGroups();
        unawaited(_sendProfile(gid));
        return;
      } on GroupCryptoException {
        continue;
      }
    }
  }

  Future<void> _drop(String gid) async {
    for (final s
        in _groupSubs.remove(gid) ?? const <StreamSubscription<Object?>>[]) {
      await s.cancel();
    }
    _groups.remove(gid);
    _rosters.remove(gid);
    try {
      await _change({'op': 'forget', 'gid': gid});
    } on GroupCryptoException {
      // Already forgotten.
    }
    _emitGroups();
  }

  void _watch(String gid) {
    final subs = <StreamSubscription<Object?>>[];
    subs.add(
      _db.doc('groups/$gid').snapshots().listen((s) {
        final data = s.data();
        if (data == null) return;
        _rosters[gid] = data;
        unawaited(_serial(() => _maintain(gid, data)));
      }, onError: (_) {}),
    );
    // Administrators add accounts once they accept their invitation.
    subs.add(
      _db
          .collection('groups/$gid/invites')
          .where('status', isEqualTo: 'accepted')
          .snapshots()
          .listen((s) {
            final roster = _rosters[gid];
            if (s.docs.isNotEmpty && roster != null) {
              unawaited(_serial(() => _maintain(gid, roster)));
            }
          }, onError: (_) {}),
    );
    subs.add(
      _db
          .collection('groups/$gid/commits')
          .where('e', isGreaterThanOrEqualTo: _groups[gid]?.epoch ?? 0)
          .snapshots()
          .listen((s) => _serial(() => _onCommits(gid, s)), onError: (_) {}),
    );
    final cursor = _cursor(gid);
    var events = _db.collection('groups/$gid/events').orderBy('at');
    if (cursor != null) events = events.startAfter([cursor]);
    subs.add(
      events.snapshots().listen(
        (s) => _serial(() => _onEvents(gid, s.docs)),
        onError: (_) {},
      ),
    );
    _groupSubs[gid] = subs;
  }

  static String _slot(int epoch) => '$epoch'.padLeft(12, '0');

  Timestamp? _cursor(String gid) {
    final raw = _file.app('cursor:$gid');
    if (raw == null) return null;
    final micros = int.tryParse(utf8.decode(raw));
    return micros == null ? null : Timestamp.fromMicrosecondsSinceEpoch(micros);
  }

  Map<String, List<int>?> _cursorAt(String gid, Object? at) => at is Timestamp
      ? {'cursor:$gid': utf8.encode('${at.microsecondsSinceEpoch}')}
      : const {};

  // ---------------------------------------------------------------- commits

  Future<void> _onCommits(
    String gid,
    QuerySnapshot<Map<String, dynamic>> snap,
  ) async {
    // In epoch order (sorted here; the query only skips old Commits).
    final docs = [...snap.docs]
      ..sort(
        (a, b) => ((a.data()['e'] as num?) ?? 0).compareTo(
          (b.data()['e'] as num?) ?? 0,
        ),
      );
    for (final doc in docs) {
      final info = _groups[gid];
      if (info == null || _closed) return;
      final epoch = (doc.data()['e'] as num?)?.toInt();
      if (doc.id != _slot(epoch ?? -1)) continue; // not a slot document
      if (epoch == null || epoch < info.epoch) continue;
      if (epoch > info.epoch) return; // a gap: wait for the missing Commit
      await _applyCommit(gid, doc.data());
    }
  }

  Future<void> _applyCommit(String gid, Map<String, dynamic> doc) async {
    final before = _groups[gid]!;
    final mine = doc['by'] == uid && doc['device'] == deviceId;
    if (_pending.contains(gid)) {
      _pending.remove(gid);
      if (mine) {
        final result = await _change({'op': 'merge_pending', 'gid': gid});
        _afterCommit(gid, result);
        return;
      }
      // Another Commit won this epoch.
      await _change({'op': 'discard_pending', 'gid': gid});
    }
    final ct = doc['ct'];
    if (ct is! Blob) return;
    final kind = doc['kind'];
    final roster =
        _rosters[gid]?['members'] as Map<String, dynamic>? ?? const {};
    try {
      final result = await _change({
        'op': 'process',
        'gid': gid,
        'message': b64(ct.bytes),
      }, check: (r) => _commitAllowed(before, r, kind, roster, doc['by']));
      _afterCommit(gid, result);
    } on GroupCryptoException {
      // An invalid or refused Commit changes nothing here; the group waits for
      // a valid one (proposal, "Event ordering").
    }
  }

  bool _commitAllowed(
    GroupInfo before,
    Map<String, dynamic> r,
    Object? kind,
    Map<String, dynamic> roster,
    Object? by,
  ) {
    if (r['kind'] != 'commit') return false;
    final committer = (r['committer'] as Map)['uid'] as String;
    if (committer != by) return false;
    final added = (r['added'] as List).cast<Map>();
    final removed = (r['removed'] as List).cast<Map>();
    final admin = before.isAdmin(committer);
    final admins = (r['admins'] as List).cast<String>().toSet();
    final wereAdmins = {
      for (final m in before.members)
        if (m.admin) m.uid,
    };
    final metaChanged =
        r['name'] != before.name ||
        admins.length != wereAdmins.length ||
        !admins.containsAll(wereAdmins);
    if (metaChanged && !admin) return false;
    if (kind == 'update' || kind == 'meta') {
      return added.isEmpty && removed.isEmpty;
    }
    final addsOk = added.every((m) => admin || m['uid'] == committer);
    final removesOk = removed.every((m) {
      if (admin) return true;
      // Fenced by the server: no longer in its roster for that device.
      final member = roster[m['uid']] as Map?;
      final devices = (member?['devices'] as List?)?.cast<String>() ?? const [];
      return !devices.contains(m['device']);
    });
    return addsOk && removesOk;
  }

  void _afterCommit(String gid, Map<String, dynamic> result) {
    final info = GroupInfo.fromCore(result);
    if (!info.active) {
      unawaited(_serial(() => _drop(gid)));
      return;
    }
    _groups[gid] = info;
    _emitGroups();
    final waiting = _waiting.remove(gid);
    if (waiting != null) unawaited(_serial(() => _onEvents(gid, waiting)));
  }

  /// Work the group needs from any member: finalising a removal the server
  /// fenced, and (administrators) adding accounts that accepted.
  Future<void> _maintain(String gid, Map<String, dynamic> roster) async {
    final info = _groups[gid];
    if (info == null || _pending.contains(gid)) return;
    final fence = (roster['fence'] as List?)?.cast<Map>() ?? const [];
    if (fence.isNotEmpty) {
      final members =
          (_crypto.call({'op': 'info', 'gid': gid})['members'] as List)
              .cast<Map>();
      final leaves = [
        for (final m in members)
          for (final f in fence)
            if (f['uid'] == m['uid'] &&
                ((f['devices'] as List?) ?? const []).contains(m['device']))
              m['leaf'],
      ];
      if (leaves.isEmpty) return;
      await _ownCommit(
        gid,
        {'op': 'commit_remove', 'gid': gid, 'leaves': leaves},
        (r) => _requests.group(gid, 'finalize', {
          'epoch': info.epoch,
          'device': deviceId,
          'commit': Blob(unb64(r['commit'] as String)),
        }),
      );
      return;
    }
    if (!info.isAdmin(uid)) return;
    final accepted = await _db
        .collection('groups/$gid/invites')
        .where('status', isEqualTo: 'accepted')
        .limit(1)
        .get();
    if (accepted.docs.isEmpty) return;
    final invite = accepted.docs.first;
    final devices = ((invite.data()['devices'] as List?) ?? const [])
        .cast<String>();
    final packages = <Map<String, Object>>[];
    final bytes = <String>[];
    for (final d in devices) {
      final p = await _db
          .collection('users/${invite.id}/devices/$d/mlsPackages')
          .limit(1)
          .get();
      if (p.docs.isEmpty) return;
      final kp = p.docs.first.data()['kp'];
      if (kp is! Blob) return;
      packages.add({'device': d, 'slot': p.docs.first.id});
      bytes.add(b64(kp.bytes));
    }
    await _ownCommit(
      gid,
      {'op': 'commit_add', 'gid': gid, 'keyPackages': bytes},
      (r) => _requests.group(gid, 'add', {
        'uid': invite.id,
        'epoch': info.epoch,
        'device': deviceId,
        'commit': Blob(unb64(r['commit'] as String)),
        'welcome': Blob(unb64(r['welcome'] as String)),
        'packages': packages,
      }),
    );
  }

  /// Prepares this device's Commit, saves it as pending and publishes it. The
  /// Commit listener later merges it (it won its epoch) or discards it.
  Future<void> _ownCommit(
    String gid,
    Map<String, dynamic> request,
    Future<void> Function(Map<String, dynamic> result) publish,
  ) async {
    final result = await _change(request);
    _pending.add(gid);
    try {
      await publish(result);
    } on GroupRefused {
      if (_pending.remove(gid)) {
        await _change({'op': 'discard_pending', 'gid': gid});
      }
    } on FirebaseException {
      if (_pending.remove(gid)) {
        await _change({'op': 'discard_pending', 'gid': gid});
      }
    } on TimeoutException {
      // Unknown: the Commit slot decides when it appears.
    }
  }

  // ---------------------------------------------------------------- events

  Future<void> _onEvents(
    String gid,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    for (final doc in docs) {
      final info = _groups[gid];
      if (info == null || _closed) return;
      final data = doc.data();
      final epoch = (data['epoch'] as num?)?.toInt() ?? -1;
      if (epoch > info.epoch) {
        (_waiting[gid] ??= []).add(doc);
        continue;
      }
      if (await _messages.has(groupChatId(gid), doc.id)) continue;
      // This device's own messages are saved when sent; MLS cannot decrypt them.
      if (data['device'] == deviceId) continue;
      final ct = data['ct'];
      if (ct is! Blob) continue;
      try {
        await _change(
          {'op': 'process', 'gid': gid, 'message': b64(ct.bytes)},
          // The authenticated sender and id must be what the server says.
          check: (r) =>
              r['kind'] == 'application' &&
              (r['sender'] as Map)['uid'] == data['by'] &&
              (r['sender'] as Map)['device'] == data['device'] &&
              utf8.decode(unb64(r['aad'] as String)) == doc.id,
          extra: _cursorAt(gid, data['at']),
          beforeSave: (r) =>
              _store(gid, doc.id, data, unb64(r['plain'] as String)),
        );
      } on GroupCryptoException {
        // Undecryptable (too old, or not for this device): skip it.
      }
    }
  }

  Future<void> _store(
    String gid,
    String id,
    Map<String, dynamic> data,
    List<int> plain,
  ) async {
    final sender = data['by'] as String;
    try {
      final json = jsonDecode(utf8.decode(plain));
      if (json is Map && json['type'] == 'profile' && json['color'] is String) {
        (_colors[gid] ??= {})[sender] = json['color'] as String;
        await _saveColors();
        if (!_colorsCtrl.isClosed) _colorsCtrl.add(gid);
        return;
      }
    } catch (_) {
      // Not a profile message.
    }
    final decoded = decodeMessagePayload(plain);
    if (decoded.mutation != null) return; // reactions and edits: later version
    await _messages.add(
      LocalMessage(
        id: id,
        chatId: groupChatId(gid),
        senderUid: sender,
        senderDevice: data['device'] as String,
        outgoing: sender == uid,
        sentAt: (data['at'] as Timestamp?)?.toDate() ?? _now(),
        body: decoded.body,
        status: decoded.status,
        quote: decoded.quote,
      ),
    );
  }

  // ---------------------------------------------------------------- sending

  /// Encrypts and publishes one text message. The message is saved first
  /// (unconfirmed); a definite refusal removes it, an unknown outcome keeps
  /// it unconfirmed, and it is never resent automatically.
  Future<void> send(String gid, String text) => _publish(
    gid,
    encodeMessagePayload(text: text, now: _now()),
    text: text,
  );

  /// This account's primary colour name, kept current by the app layer.
  String ownColor = 'ember';

  Future<void> _sendProfile(String gid) async {
    try {
      await _publish(
        gid,
        utf8.encode(jsonEncode({'v': 4, 'type': 'profile', 'color': ownColor})),
      );
    } catch (_) {
      // Shared again with the next change; members show Stone meanwhile.
    }
  }

  /// Shares this account's colour with every group (after a change in Settings).
  Future<void> shareColor() async {
    for (final gid in _groups.keys) {
      await _sendProfile(gid);
    }
  }

  Future<void> _publish(String gid, List<int> payload, {String? text}) async {
    final n = _now().microsecondsSinceEpoch;
    final id = '$deviceId-$n';
    final chatId = groupChatId(gid);
    final result = await _serial(() async {
      if (!_groups.containsKey(gid)) throw StateError('Not in this group.');
      return _change({
        'op': 'encrypt',
        'gid': gid,
        'plain': b64(payload),
        'aad': b64(utf8.encode(id)),
      });
    });
    final sentAt = _now();
    LocalMessage local(MessageStatus status) => LocalMessage(
      id: id,
      chatId: chatId,
      senderUid: uid,
      senderDevice: deviceId,
      outgoing: true,
      sentAt: sentAt,
      body: text ?? '',
      status: status,
    );
    if (text != null) await _messages.add(local(MessageStatus.unconfirmed));
    final ref = _db.doc('groups/$gid/events/$id');
    final limit = _db.doc('users/$uid/limits/send');
    final doc = {
      'by': uid,
      'device': deviceId,
      'n': n,
      'epoch': result['epoch'],
      'ct': Blob(unb64(result['ciphertext'] as String)),
      'at': FieldValue.serverTimestamp(),
      'expireAt': Timestamp.fromDate(sentAt.add(const Duration(days: 30))),
    };
    try {
      await publishWithClock(
        allowance: _allowance,
        retryable: (e) =>
            e is FirebaseException && e.code == 'permission-denied',
        pauses: const [Duration(milliseconds: 300), Duration(seconds: 1)],
        publish: (clock) {
          final at = FieldValue.serverTimestamp();
          final one = FieldValue.increment(1);
          final batch = _db.batch()..set(ref, doc);
          switch (clock) {
            case SendClock.day:
              batch.set(limit, {
                'at': at,
                'window': at,
                'sent': 1,
                'day': at,
                'today': 1,
              });
            case SendClock.window:
              batch.update(limit, {
                'at': at,
                'window': at,
                'sent': 1,
                'today': one,
              });
            case SendClock.next:
              batch.update(limit, {'at': at, 'sent': one, 'today': one});
            case SendClock.dayInWindow:
              batch.update(limit, {
                'at': at,
                'day': at,
                'today': 1,
                'sent': one,
              });
          }
          return batch.commit().timeout(const Duration(seconds: 20));
        },
      );
      if (text != null) await _messages.add(local(MessageStatus.ok));
    } on FirebaseException {
      // Refused in every form: nothing was published.
      if (text != null) await _messages.remove(chatId, id);
      rethrow;
    }
  }

  // ---------------------------------------------------------------- membership

  /// Creates a group and invites [members] (uids of accepted 1:1 contacts).
  Future<String> create(String name, List<String> members) async {
    final gid = b64(randomBytes(16))
        .replaceAll('+', '-')
        .replaceAll('/', '_')
        .replaceAll('=', '');
    final result = await _serial(
      () => _change({'op': 'create', 'gid': gid, 'name': name}),
    );
    try {
      await _requests.account('create', {
        'gid': gid,
        'devices': [deviceId],
        'epoch': result['epoch'] as int,
      });
    } catch (_) {
      await _serial(() => _change({'op': 'forget', 'gid': gid}));
      rethrow;
    }
    _groups[gid] = GroupInfo.fromCore(result);
    _emitGroups();
    // The server's reference may have arrived before the group was recorded
    // here; start watching it now either way.
    if (!_groupSubs.containsKey(gid)) _watch(gid);
    unawaited(_sendProfile(gid));
    for (final m in members) {
      await invite(gid, m).catchError((Object _) {});
    }
    return gid;
  }

  Future<void> invite(String gid, String memberUid) =>
      _requests.group(gid, 'invite', {'uid': memberUid});

  Future<void> accept(String gid) => _requests.account('accept', {
    'gid': gid,
    'devices': [deviceId],
  });

  Future<void> decline(String gid) =>
      _requests.account('decline', {'gid': gid});

  /// Leaving stops reading at once; a remaining member's Commit removes this
  /// account's devices afterwards.
  Future<void> leave(String gid) async {
    await _requests.group(gid, 'leave', {});
    await _serial(() => _drop(gid));
  }

  Future<void> remove(String gid, String memberUid) => _serial(() async {
    final info = _groups[gid]!;
    final members =
        (_crypto.call({'op': 'info', 'gid': gid})['members'] as List)
            .cast<Map>();
    final leaves = [
      for (final m in members)
        if (m['uid'] == memberUid) m['leaf'],
    ];
    await _ownCommit(
      gid,
      {'op': 'commit_remove', 'gid': gid, 'leaves': leaves},
      (r) => _requests.group(gid, 'remove', {
        'uid': memberUid,
        'epoch': info.epoch,
        'device': deviceId,
        'commit': Blob(unb64(r['commit'] as String)),
      }),
    );
  });

  /// Renames the group: a Commit any member's device can apply, accepted from
  /// administrators only.
  Future<void> rename(String gid, String name) => _serial(() async {
    final info = _groups[gid]!;
    await _ownCommit(gid, {'op': 'commit_meta', 'gid': gid, 'name': name}, (
      r,
    ) async {
      final batch = _db.batch()
        ..set(_db.doc('groups/$gid/commits/${_slot(info.epoch)}'), {
          'e': info.epoch,
          'by': uid,
          'device': deviceId,
          'kind': 'meta',
          'ct': Blob(unb64(r['commit'] as String)),
          'at': FieldValue.serverTimestamp(),
        })
        ..update(_db.doc('groups/$gid'), {'epoch': info.epoch + 1});
      await batch.commit();
    });
  });

  // ---------------------------------------------------------------- colours

  Future<void> _loadColors() async {
    final raw = await _secrets.read('groupcolors:$uid');
    if (raw == null) return;
    final json = jsonDecode(raw) as Map;
    for (final e in json.entries) {
      _colors['${e.key}'] = (e.value as Map).map(
        (k, v) => MapEntry('$k', '$v'),
      );
    }
  }

  Future<void> _saveColors() =>
      _secrets.write('groupcolors:$uid', jsonEncode(_colors));
}
