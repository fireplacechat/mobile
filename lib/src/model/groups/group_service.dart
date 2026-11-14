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
import 'package:fireplace/src/db/message_mutation.dart';
import 'package:fireplace/src/model/chat/message_limits.dart';
import 'package:fireplace/src/model/chat/message_payload.dart';
import 'package:fireplace/src/model/chat/send_allowance.dart';
import 'package:fireplace/src/model/groups/group_models.dart';
import 'package:fireplace/src/model/groups/group_requests.dart';
import 'package:fireplace/src/model/keys/key_service.dart';
import 'package:flutter/foundation.dart';

/// Group chats for one account on this device (mobile decision 0050,
/// `docs/protocol/group-chats-v1.md`, backend decision 0023).
///
/// All MLS work runs one call at a time. Each change from the core is checked,
/// saved (MLS records and this service's cursors together, atomically) and
/// only then accepted, so a crash loses nothing and repeats nothing.
///
/// Commits are applied strictly in epoch order. A Commit is checked against
/// the group's rules before it is kept: a rename or role change only from an
/// administrator; a self-update adds and removes nobody; members are removed
/// only by administrators or once the server has fenced them.
///
/// An invitation does the MLS Add (round 2): the inviter's device sends the
/// Commit and the Welcome with the request, so the invited person joins from
/// the Welcome they already have, with no other phone involved.
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
    this._colourCatchUp = const Duration(seconds: 5),
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
  final Duration _colourCatchUp;

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
  // Joined from the Welcome here, while the server's answer is on its way.
  final _joining = <String>{};
  final _rosterCtrl = StreamController<String>.broadcast();
  // What a member said before going ("left"), or an administrator before
  // removing them: tells a removal's line which words to use.
  final _departures = <String, Map<String, GroupNotice>>{};
  final _removalLines = <String, Map<String, LocalMessage>>{};
  // Groups whose members have been asked for their colours since the app started.
  final _askedColours = <String>{};

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

  /// A group's history on this device, newest last.
  Stream<List<LocalMessage>> watchMessages(String gid) =>
      _messages.watch(groupChatId(gid));

  MemberColors colorsOf(String gid) =>
      Map.unmodifiable(_colors[gid] ?? const {});
  Stream<String> get colorChanges => _colorsCtrl.stream;

  /// People invited who have not answered yet, and who invited each. They are
  /// in the MLS group already; the server's roster says they have not joined.
  Map<String, String> invitedTo(String gid) {
    final invited = _rosters[gid]?['invited'];
    return {
      if (invited is Map)
        for (final e in invited.entries)
          '${e.key}': '${(e.value as Map?)?['by'] ?? ''}',
    };
  }

  /// Fires with a group's id when the server's roster for it changes.
  Stream<String> get rosterChanges => _rosterCtrl.stream;

  /// True when this device joined a group that already existed, so its
  /// history here starts after the group began.
  bool joinedLater(String gid) => _file.app('newcomer:$gid') != null;

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
    await _rosterCtrl.close();
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
      _joining.remove(gid);
      // Joined on another of this account's devices, or before a reinstall.
      if (!_groups.containsKey(gid) && await _joinFromWelcome(gid)) {
        _askedColours.add(gid);
        unawaited(_sendProfile(gid, hello: true));
      }
      if (_groups.containsKey(gid)) {
        await _noteSince(gid, entry.value['joinedAt']);
        if (!_groupSubs.containsKey(gid)) _watch(gid);
      }
    }
    // Removed by the server (left, removed, fenced): stop and forget the
    // group's keys. Its history stays on this device.
    for (final gid in [..._groups.keys]) {
      if (!listed.containsKey(gid) && !_joining.contains(gid)) await _drop(gid);
    }
  }

  /// Joins from the Welcome the invitation left for this account. The Welcome
  /// is from the epoch of the invitation, which may be long past: the Commit
  /// listener then brings this device up to date.
  Future<bool> _joinFromWelcome(String gid) async {
    final welcomes = await _db
        .collection('groups/$gid/welcomes')
        .where('uid', isEqualTo: uid)
        .get();
    for (final w in welcomes.docs) {
      final ct = w.data()['ct'];
      if (ct is! Blob) continue;
      try {
        // A Welcome for another of this account's devices, or an invitation
        // that has since ended, is refused; try the next.
        final result = await _change(
          {'op': 'join', 'welcome': b64(ct.bytes)},
          extra: {
            'newcomer:$gid': [1],
          },
        );
        final info = GroupInfo.fromCore(result);
        if (info.gid != gid) continue;
        _groups[gid] = info;
        _emitGroups();
        return true;
      } on GroupCryptoException {
        continue;
      }
    }
    return false;
  }

  /// When the server put this account in the roster. Messages from before it
  /// are not shown (0050: a newcomer sees no earlier history), though an
  /// invited device holds the keys from the moment of the invitation.
  Timestamp? _since(String gid) {
    final raw = _file.app('since:$gid');
    final micros = raw == null ? null : int.tryParse(utf8.decode(raw));
    return micros == null ? null : Timestamp.fromMicrosecondsSinceEpoch(micros);
  }

  Future<void> _noteSince(String gid, Object? joinedAt) async {
    if (joinedAt is! Timestamp || _file.app('since:$gid') != null) return;
    _file.setApp({
      'since:$gid': utf8.encode('${joinedAt.microsecondsSinceEpoch}'),
    });
    await _file.save();
  }

  Future<void> _drop(String gid) async {
    for (final s
        in _groupSubs.remove(gid) ?? const <StreamSubscription<Object?>>[]) {
      await s.cancel();
    }
    _groups.remove(gid);
    _rosters.remove(gid);
    _departures.remove(gid);
    _removalLines.remove(gid);
    try {
      await _change(
        {'op': 'forget', 'gid': gid},
        extra: {'since:$gid': null, 'newcomer:$gid': null},
      );
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
        if (!_rosterCtrl.isClosed) _rosterCtrl.add(gid);
        unawaited(_serial(() => _maintain(gid, data)));
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
    final since = _since(gid);
    var events = _db.collection('groups/$gid/events').orderBy('at');
    if (cursor != null) {
      events = events.startAfter([cursor]);
    } else if (since != null) {
      // A newcomer reads nothing from before they joined.
      events = events.startAt([since]);
    }
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
        await _afterCommit(gid, result, before: before, by: uid, at: doc['at']);
        return;
      }
      // Another Commit won this epoch.
      await _change({'op': 'discard_pending', 'gid': gid});
    }
    final ct = doc['ct'];
    if (ct is! Blob) return;
    final kind = doc['kind'];
    if (kind == 'membership') {
      // A removal by someone who is not an administrator is allowed only for
      // devices the server has fenced. The roster held here may be older than
      // this Commit, so read it again (one read per membership change).
      try {
        final fresh = (await _db.doc('groups/$gid').get()).data();
        if (fresh != null) _rosters[gid] = fresh;
      } on FirebaseException {
        // Offline: check against the roster already here.
      }
    }
    final roster =
        _rosters[gid]?['members'] as Map<String, dynamic>? ?? const {};
    try {
      final result = await _change({
        'op': 'process',
        'gid': gid,
        'message': b64(ct.bytes),
      }, check: (r) => _commitAllowed(before, r, kind, roster, doc['by']));
      await _afterCommit(
        gid,
        result,
        before: before,
        by: '${doc['by']}',
        at: doc['at'],
      );
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
    // Any member may add someone by inviting them (owner's choice). The server
    // allows it only for a contact of the inviter. An Add is not checked
    // against the roster: by the time a phone that was offline sees it, the
    // person may have declined, and refusing would leave this phone stuck.
    const addsOk = true;
    final removesOk = removed.every((m) {
      if (admin) return true;
      // Fenced by the server: no longer in its roster for that device.
      final member = roster[m['uid']] as Map?;
      final devices = (member?['devices'] as List?)?.cast<String>() ?? const [];
      return !devices.contains(m['device']);
    });
    return addsOk && removesOk;
  }

  Future<void> _afterCommit(
    String gid,
    Map<String, dynamic> result, {
    required GroupInfo before,
    required String by,
    Object? at,
  }) async {
    final info = GroupInfo.fromCore(result);
    await _writeNotices(gid, before, info, by, at);
    if (!info.active) {
      unawaited(_serial(() => _drop(gid)));
      return;
    }
    _groups[gid] = info;
    _emitGroups();
    final waiting = _waiting.remove(gid);
    if (waiting != null) unawaited(_serial(() => _onEvents(gid, waiting)));
  }

  /// Writes the lines for one Commit ("alice added bob_jones") into the
  /// history, from the MLS state before and after it. The Commit's author is
  /// the one MLS authenticated.
  Future<void> _writeNotices(
    String gid,
    GroupInfo before,
    GroupInfo after,
    String by,
    Object? at,
  ) async {
    final was = {for (final m in before.members) m.uid};
    final now = {for (final m in after.members) m.uid};
    final wasAdmin = {
      for (final m in before.members)
        if (m.admin) m.uid,
    };
    final nowAdmin = {
      for (final m in after.members)
        if (m.admin) m.uid,
    };
    final notices = <GroupNotice>[
      for (final who in now.difference(was))
        GroupNotice(GroupNoticeKind.added, by: by, who: who),
      for (final who in was.difference(now))
        _departures[gid]?.remove(who) ??
            GroupNotice(GroupNoticeKind.gone, who: who),
      for (final who in nowAdmin.difference(wasAdmin))
        if (was.contains(who))
          GroupNotice(GroupNoticeKind.madeAdmin, by: by, who: who),
      for (final who in wasAdmin.difference(nowAdmin))
        if (now.contains(who))
          GroupNotice(GroupNoticeKind.removedAdmin, by: by, who: who),
      if (after.name != before.name)
        GroupNotice(GroupNoticeKind.renamed, by: by),
    ];
    final sentAt = at is Timestamp ? at.toDate() : _now();
    for (var i = 0; i < notices.length; i++) {
      final line = LocalMessage(
        id: 'notice-${_slot(before.epoch)}-$i',
        chatId: groupChatId(gid),
        senderUid: by,
        senderDevice: '',
        outgoing: false,
        sentAt: sentAt,
        body: notices[i].encode(),
        status: MessageStatus.notice,
      );
      if (notices[i].kind == GroupNoticeKind.gone) {
        (_removalLines[gid] ??= {})[notices[i].who!] = line;
      }
      await _messages.add(line);
    }
  }

  /// A member said they are leaving, or an administrator that they are
  /// removing someone. Both are encrypted group messages, so MLS vouches for
  /// who said it. The removal's line then says "left" or "removed".
  Future<void> _onDeparture(
    String gid,
    String sender,
    Map<dynamic, dynamic> json,
  ) async {
    final GroupNotice notice;
    final String who;
    if (json['kind'] == 'left') {
      who = sender;
      notice = GroupNotice(GroupNoticeKind.left, who: sender);
    } else if (json['kind'] == 'removing' &&
        json['uid'] is String &&
        (_groups[gid]?.isAdmin(sender) ?? false)) {
      who = json['uid'] as String;
      notice = GroupNotice(GroupNoticeKind.removed, by: sender, who: who);
    } else {
      return;
    }
    // The removal may already be in the history, worded without a reason.
    final line = _removalLines[gid]?.remove(who);
    if (line != null) {
      await _messages.add(line.copyWith(body: notice.encode()));
    } else {
      (_departures[gid] ??= {})[who] = notice;
    }
  }

  /// Work the group needs from any member: ending an invitation nobody
  /// answered in seven days, and finalising a removal the server fenced.
  Future<void> _maintain(String gid, Map<String, dynamic> roster) async {
    final info = _groups[gid];
    if (info == null || _pending.contains(gid)) return;
    _catchUpColours(gid);
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
    // The server has no scheduler, so the first member's phone to notice an
    // invitation past its seven days asks the server to end it. The server
    // then fences those devices and the next roster change finalises.
    final invited = roster['invited'];
    if (invited is! Map) return;
    for (final e in invited.entries) {
      final expireAt = (e.value as Map?)?['expireAt'];
      if (expireAt is Timestamp && expireAt.toDate().isBefore(_now())) {
        try {
          await _requests.group(gid, 'expire', {'uid': '${e.key}'});
        } catch (_) {
          // Another member's phone got there first, or it will be tried again.
        }
        return;
      }
    }
  }

  /// Prepares this device's Commit, saves it as pending and publishes it.
  /// Once the server has taken it, it holds its epoch's slot, so it is merged
  /// here at once; the next change can then follow without waiting for the
  /// Commit listener. A refusal discards it, and with [strict] is passed on to
  /// the caller to show. An unknown outcome leaves it for the listener, which
  /// merges it if it won its epoch and discards it otherwise.
  Future<void> _ownCommit(
    String gid,
    Map<String, dynamic> request,
    Future<void> Function(Map<String, dynamic> result) publish, {
    bool strict = false,
  }) async {
    final before = _groups[gid]!;
    final result = await _change(request);
    _pending.add(gid);
    try {
      await publish(result);
    } on GroupRefused {
      await _discardPending(gid);
      if (strict) rethrow;
      return;
    } on FirebaseException {
      await _discardPending(gid);
      if (strict) rethrow;
      return;
    } on TimeoutException {
      // Unknown: the Commit slot decides when it appears.
      if (strict) rethrow;
      return;
    }
    if (_pending.remove(gid)) {
      final merged = await _change({'op': 'merge_pending', 'gid': gid});
      await _afterCommit(gid, merged, before: before, by: uid);
    }
  }

  Future<void> _discardPending(String gid) async {
    if (_pending.remove(gid)) {
      await _change({'op': 'discard_pending', 'gid': gid});
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
      // From before this account joined: not shown, even where the keys allow.
      final since = _since(gid);
      final at = data['at'];
      if (since != null && at is Timestamp && at.compareTo(since) < 0) continue;
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
        // Someone has just joined and has nobody's colour yet: send them this
        // account's (one small message per member per newcomer, at most 15).
        if (json['hello'] == true && sender != uid) {
          unawaited(_sendProfile(gid));
        }
        return;
      }
      if (json is Map && json['type'] == 'notice') {
        await _onDeparture(gid, sender, json);
        return;
      }
    } catch (_) {
      // Not a profile message.
    }
    final decoded = decodeMessagePayload(plain);
    // Edits, reactions and deletes are stored like 1:1 ones: the history's
    // projection applies an edit or delete only from the message's author.
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
        mutation: decoded.mutation,
      ),
    );
  }

  // ---------------------------------------------------------------- sending

  /// Edits one of this account's own messages, for everyone (up to 10 times
  /// within 24 hours, as in 1:1 chats).
  Future<void> edit(String gid, String targetId, String body) async {
    final target = await _own(gid, targetId);
    final age = _now().difference(target.sentAt);
    if (age.isNegative ||
        age > const Duration(hours: 24) ||
        target.editClock >= 10) {
      throw GroupActionError(
        'You can edit your messages up to 10 times within 24 hours.',
      );
    }
    if (body.trim() == target.body) {
      throw GroupActionError('Make a change before saving.');
    }
    if (messageTooLong(body)) throw GroupActionError(messageLimitError);
    await _control(
      gid,
      MessageMutation(
        kind: MessageMutationKind.edit,
        targetId: targetId,
        body: body.trim(),
        revision: target.editClock + 1,
      ),
    );
  }

  /// Deletes one of this account's own messages for everyone.
  Future<void> deleteForEveryone(String gid, String targetId) async {
    await _own(gid, targetId);
    await _control(
      gid,
      MessageMutation(kind: MessageMutationKind.delete, targetId: targetId),
    );
  }

  /// Adds, changes or (the same emoji again) removes this account's reaction.
  Future<void> react(String gid, String targetId, String emoji) async {
    final target = await _messages.get(groupChatId(gid), targetId);
    if (target == null || !target.visible) {
      throw GroupActionError('That message is no longer here.');
    }
    final previous = target.reactions[uid];
    await _control(
      gid,
      MessageMutation(
        kind: MessageMutationKind.reaction,
        targetId: targetId,
        emoji: emoji,
        operation: previous?.emoji == emoji
            ? ReactionOperation.clear
            : ReactionOperation.set,
        revision: (target.reactionClocks[uid] ?? previous?.revision ?? 0) + 1,
      ),
    );
  }

  /// Removes a message from this phone only.
  Future<void> deleteLocally(String gid, String messageId) =>
      _messages.add(LocalMessage.tombstone(groupChatId(gid), messageId));

  Future<LocalMessage> _own(String gid, String targetId) async {
    final target = await _messages.get(groupChatId(gid), targetId);
    if (target == null || target.senderUid != uid || target.remotelyDeleted) {
      throw GroupActionError('You can only change your own messages.');
    }
    return target;
  }

  Future<void> _control(String gid, MessageMutation mutation) {
    final checked = MessageMutation.fromJson(mutation.toJson());
    return _publish(
      gid,
      encodeMessagePayload(text: '', now: _now(), mutation: checked),
      mutation: checked,
    );
  }

  /// Encrypts and publishes one text message. The message is saved first
  /// (unconfirmed); a definite refusal removes it, an unknown outcome keeps
  /// it unconfirmed, and it is never resent automatically.
  Future<void> send(String gid, String text) {
    if (messageTooLong(text)) throw GroupActionError(messageLimitError);
    return _publish(
      gid,
      encodeMessagePayload(text: text, now: _now()),
      text: text,
    );
  }

  /// This account's primary colour name, kept current by the app layer.
  String ownColor = 'ember';

  /// Shares this account's colour inside the group. With [hello], sent on
  /// joining, every member answers with theirs, so a newcomer has them all.
  Future<void> _sendProfile(String gid, {bool hello = false}) async {
    try {
      await _publish(
        gid,
        utf8.encode(
          jsonEncode({
            'v': 4,
            'type': 'profile',
            'color': ownColor,
            if (hello) 'hello': true,
          }),
        ),
      );
    } catch (_) {
      // Shared again with the next change; members show Stone meanwhile.
    }
  }

  /// Asks a group's members for their colours when this phone lacks one: a
  /// group from before colours were answered, or a colour sent while this
  /// phone could not read it. Once per group each time the app starts, and
  /// only after a pause, so a newcomer's own `hello` usually settles it first.
  /// It costs one message here and one from each member (at most 16).
  void _catchUpColours(String gid) {
    if (_askedColours.contains(gid)) return;
    bool missing() {
      final members = _rosters[gid]?['members'];
      final have = _colors[gid] ?? const {};
      return members is Map &&
          members.keys.any((u) => u != uid && !have.containsKey(u));
    }

    if (!missing()) return;
    _askedColours.add(gid);
    unawaited(
      Future<void>.delayed(_colourCatchUp, () async {
        if (_closed || !_groups.containsKey(gid) || !missing()) return;
        await _sendProfile(gid, hello: true);
      }),
    );
  }

  /// Says, inside the group, why someone is about to go. Best effort: without
  /// it the line reads "is no longer in the group".
  Future<void> _sendNotice(String gid, Map<String, Object> notice) async {
    try {
      await _publish(
        gid,
        utf8.encode(jsonEncode({'v': 4, 'type': 'notice', ...notice})),
      );
    } catch (_) {
      // The removal still happens.
    }
  }

  /// Shares this account's colour with every group (after a change in Settings).
  Future<void> shareColor() async {
    for (final gid in _groups.keys) {
      await _sendProfile(gid);
    }
  }

  Future<void> _publish(
    String gid,
    List<int> payload, {
    String? text,
    MessageMutation? mutation,
  }) async {
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
      if (mutation != null) {
        await _messages.add(
          LocalMessage(
            id: id,
            chatId: chatId,
            senderUid: uid,
            senderDevice: deviceId,
            outgoing: true,
            sentAt: sentAt,
            body: '',
            mutation: mutation,
          ),
        );
      }
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

  /// Invites [memberUid] and adds their devices to the MLS group in the same
  /// request (round 2). This phone is online now, so it does the work now: the
  /// invited person later joins from the Welcome without any other phone.
  Future<void> invite(String gid, String memberUid) => _serial(() async {
    final info = _groups[gid];
    if (info == null) throw GroupActionError('You are not in this group.');
    // Up to four of their devices that have a key package to use.
    final listed = await _db.collection('users/$memberUid/devices').get();
    final devices = <String>[];
    final packages = <Map<String, Object>>[];
    final bytes = <String>[];
    for (final d in listed.docs) {
      if (devices.length == 4) break;
      if (d.data()['revokedAt'] != null) continue;
      final p = await d.reference.collection('mlsPackages').limit(1).get();
      final kp = p.docs.firstOrNull?.data()['kp'];
      if (kp is! Blob) continue;
      devices.add(d.id);
      packages.add({'device': d.id, 'slot': p.docs.first.id});
      bytes.add(b64(kp.bytes));
    }
    if (devices.isEmpty) throw GroupRefused('packages');
    await _ownCommit(
      gid,
      {'op': 'commit_add', 'gid': gid, 'keyPackages': bytes},
      (r) => _requests.group(gid, 'invite', {
        'uid': memberUid,
        'epoch': info.epoch,
        'device': deviceId,
        'devices': devices,
        'commit': Blob(unb64(r['commit'] as String)),
        'welcome': Blob(unb64(r['welcome'] as String)),
        'packages': packages,
      }),
      strict: true,
    );
  });

  /// Joins a group this account was invited to. The Welcome is already here,
  /// so the group opens at once; the server then moves the account into the
  /// roster, which lets this phone read and send.
  Future<void> accept(String gid) async {
    final joined = await _serial(() async {
      if (_groups.containsKey(gid)) return true;
      _joining.add(gid);
      return _joinFromWelcome(gid);
    });
    if (!joined) {
      _joining.remove(gid);
      throw GroupActionError(
        'This invitation is for your other phone. Open Fireplace there to join.',
      );
    }
    try {
      await _requests.account('accept', {'gid': gid});
    } on GroupRefused {
      _joining.remove(gid);
      await _serial(() => _drop(gid));
      rethrow;
    }
    // The group stays exempt from the server's list until it appears there.
    _askedColours.add(gid);
    unawaited(_sendProfile(gid, hello: true));
  }

  Future<void> decline(String gid) =>
      _requests.account('decline', {'gid': gid});

  /// Leaving stops reading at once; a remaining member's Commit removes this
  /// account's devices afterwards.
  Future<void> leave(String gid) async {
    await _sendNotice(gid, {'kind': 'left'});
    await _requests.group(gid, 'leave', {});
    await _serial(() => _drop(gid));
  }

  /// Removes a member, or someone invited who has not answered.
  Future<void> remove(String gid, String memberUid) async {
    if (!invitedTo(gid).containsKey(memberUid)) {
      await _sendNotice(gid, {'kind': 'removing', 'uid': memberUid});
      // This phone does not read its own messages back.
      (_departures[gid] ??= {})[memberUid] = GroupNotice(
        GroupNoticeKind.removed,
        by: uid,
        who: memberUid,
      );
    }
    await _serial(() async {
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
        strict: true,
      );
    });
  }

  /// Makes a member an administrator, or stops them being one: an MLS Commit
  /// carrying the new list, which every phone accepts from administrators
  /// only, and the same list to the server for its roster.
  Future<void> setAdmin(String gid, String memberUid, {required bool admin}) =>
      _serial(() async {
        final info = _groups[gid];
        if (info == null || !info.isAdmin(uid)) {
          throw GroupActionError('Only administrators can do that.');
        }
        final joined = {
          for (final m in info.members)
            if (!invitedTo(gid).containsKey(m.uid)) m.uid,
        };
        // When nobody on the list is still here, everybody administers.
        var admins = {
          for (final m in info.members)
            if (m.admin && joined.contains(m.uid)) m.uid,
        };
        if (admins.isEmpty) admins = {...joined};
        if (!joined.contains(memberUid)) {
          throw GroupActionError(
            'They can be an administrator once they have joined.',
          );
        }
        admin ? admins.add(memberUid) : admins.remove(memberUid);
        if (admins.isEmpty) {
          throw GroupActionError('A group needs at least one administrator.');
        }
        final list = admins.toList()..sort();
        await _ownCommit(
          gid,
          {'op': 'commit_meta', 'gid': gid, 'admins': list},
          (r) => _requests.group(gid, 'roles', {
            'admins': list,
            'epoch': info.epoch,
            'device': deviceId,
            'commit': Blob(unb64(r['commit'] as String)),
          }),
          strict: true,
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

  /// Publishes a rename or role Commit without asking whether this account
  /// may. The app never does: tests use it to show other phones refuse it.
  @visibleForTesting
  Future<void> commitMetaUnchecked(
    String gid, {
    String? name,
    List<String>? admins,
  }) => _serial(() async {
    final info = _groups[gid]!;
    await _ownCommit(
      gid,
      {'op': 'commit_meta', 'gid': gid, 'name': ?name, 'admins': ?admins},
      (r) async {
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
      },
    );
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
