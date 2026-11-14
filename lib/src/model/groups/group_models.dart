/// Group chats (mobile decision 0050, `docs/protocol/group-chats-v1.md`).
///
/// Off unless the app is built with `--dart-define=FIREPLACE_GROUPS=true`, so
/// release builds have no groups until the release gates in 0050 are met.
const groupsEnabled = bool.fromEnvironment('FIREPLACE_GROUPS');

abstract final class GroupLimits {
  static const maxMembers = 16;
  static const maxNameChars = 40;
  static const keyPackagesPerDevice = 10;
}

/// The local history's chat id for a group. Never passed to the 1:1 code.
String groupChatId(String gid) => 'group-$gid';
bool isGroupChatId(String chatId) => chatId.startsWith('group-');
String gidOfChat(String chatId) => chatId.substring('group-'.length);

/// One member of a group, as MLS authenticated it.
class GroupMember {
  const GroupMember({
    required this.uid,
    required this.devices,
    required this.admin,
  });
  final String uid;
  final List<String> devices;
  final bool admin;
}

/// What this device knows of a group: from its MLS state, never from the
/// server's roster alone.
class GroupInfo {
  const GroupInfo({
    required this.gid,
    required this.name,
    required this.epoch,
    required this.members,
    required this.active,
  });
  final String gid;
  final String name;
  final int epoch;
  final List<GroupMember> members;

  /// False once this device has been removed.
  final bool active;

  String get chatId => groupChatId(gid);
  bool isAdmin(String uid) =>
      members.any((m) => m.uid == uid && m.admin) ||
      // When nobody administers the group, everybody does (as the server).
      !members.any((m) => m.admin);

  static GroupInfo fromCore(Map<String, dynamic> j) {
    final admins = {...(j['admins'] as List).cast<String>()};
    final byUid = <String, List<String>>{};
    for (final m in (j['members'] as List).cast<Map>()) {
      byUid
          .putIfAbsent(m['uid'] as String, () => [])
          .add(m['device'] as String);
    }
    return GroupInfo(
      gid: j['gid'] as String,
      name: j['name'] as String,
      epoch: j['epoch'] as int,
      active: j['active'] as bool,
      members: [
        for (final e in byUid.entries)
          GroupMember(
            uid: e.key,
            devices: e.value,
            admin: admins.contains(e.key),
          ),
      ],
    );
  }
}

/// An invitation waiting for this account to answer.
class GroupInvitation {
  const GroupInvitation({
    required this.gid,
    required this.inviter,
    required this.at,
  });
  final String gid;
  final String inviter;
  final DateTime at;
}

/// Each member's chosen colour name (a ChatBubbleColor's name), shared only
/// inside the group (0050).
typedef MemberColors = Map<String, String>;

/// A membership request the server refused, with its reason.
class GroupRefused implements Exception {
  GroupRefused(this.reason);
  final String reason;
  @override
  String toString() => 'Group request refused ($reason).';

  /// Plain words for people.
  String get message => switch (reason) {
    'full' => 'This group is full.',
    'limit' =>
      'You have made the most groups allowed today. Try again tomorrow.',
    'too many groups' => 'You are in the most groups allowed.',
    'not an administrator' => 'Only administrators can do that.',
    'not a contact' => 'You can invite only people you already chat with.',
    'expired' => 'This invitation has expired.',
    'no invite' => 'This invitation is no longer open.',
    _ => 'That did not work. Try again.',
  };
}

/// An action this device refused before sending, in plain words.
class GroupActionError implements Exception {
  GroupActionError(this.message);
  final String message;
  @override
  String toString() => message;
}
