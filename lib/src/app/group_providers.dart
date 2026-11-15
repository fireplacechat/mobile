import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/chat_color_preference.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/model/groups/group_models.dart';
import 'package:fireplace/src/model/groups/group_service.dart';
import 'package:fireplace/src/styles/chat_colors.dart';

/// The signed-in account's group service, or null (groups off or not ready).
final groupServiceProvider = Provider<GroupService?>(
  (ref) => ref.watch(appSessionProvider).value?.groups,
);

/// Whether this session offers groups (a build that includes them, whose
/// group service started).
final groupsOnProvider = Provider<bool>(
  (ref) => ref.watch(groupServiceProvider) != null,
);

final groupsProvider = StreamProvider.autoDispose<Map<String, GroupInfo>>((
  ref,
) {
  final service = ref.watch(groupServiceProvider);
  return service == null ? Stream.value(const {}) : service.watchGroups();
});

final groupInvitationsProvider =
    StreamProvider.autoDispose<List<GroupInvitation>>((ref) {
      final service = ref.watch(groupServiceProvider);
      return service == null
          ? Stream.value(const [])
          : service.watchInvitations();
    });

final groupMessagesProvider = StreamProvider.autoDispose
    .family<List<LocalMessage>, String>((ref, gid) {
      final service = ref.watch(groupServiceProvider);
      return service == null
          ? Stream.value(const [])
          : service.watchMessages(gid);
    });

/// Each member's colour name in one group, updated as profile messages arrive.
final groupColorsProvider = StreamProvider.autoDispose
    .family<MemberColors, String>((ref, gid) async* {
      final service = ref.watch(groupServiceProvider);
      if (service == null) {
        yield const {};
        return;
      }
      yield service.colorsOf(gid);
      await for (final changed in service.colorChanges) {
        if (changed == gid) yield service.colorsOf(gid);
      }
    });

/// People invited to a group who have not answered, with who invited each.
/// From the server's roster: MLS already counts them as members.
final groupInvitedProvider = StreamProvider.autoDispose
    .family<Map<String, String>, String>((ref, gid) async* {
      final service = ref.watch(groupServiceProvider);
      if (service == null) {
        yield const {};
        return;
      }
      yield service.invitedTo(gid);
      await for (final changed in service.rosterChanges) {
        if (changed == gid) yield service.invitedTo(gid);
      }
    });

/// The colour to show for a member: theirs once it has arrived, Stone before.
ChatBubbleColor memberColor(MemberColors colors, String uid) =>
    ChatBubbleColor.values.asNameMap()[colors[uid]] ?? ChatBubbleColor.stone;

/// Messages from other people in a group that this phone has not shown yet.
/// Counted by the history database from each message's read flag (issue
/// 180), like 1:1 chats: the server holds no read state and nobody is told
/// what was read. Zero while it is being counted.
final groupUnreadCountProvider = FutureProvider.autoDispose.family<int, String>(
  (ref, gid) async {
    final prefs = ref.watch(appSessionProvider).value?.chatPreferences;
    final service = ref.watch(groupServiceProvider);
    if (prefs == null || service == null || !prefs.available) return 0;
    final changes = prefs.changes.listen((_) => ref.invalidateSelf());
    ref.onDispose(changes.cancel);
    final id = groupChatId(gid);
    // Counted again whenever the group's history changes.
    final messages =
        ref.watch(groupMessagesProvider(gid)).value ?? const <LocalMessage>[];
    if (prefs.needsBaseline(id)) {
      // What is already here when the group first appears is not "new":
      // exactly these, so a message arriving meanwhile stays unread.
      final existing = [
        for (final m in messages)
          if (!m.outgoing) m.id,
      ];
      try {
        if (await prefs.claimBaseline(id)) {
          await service.markRead(gid, existing);
        }
      } catch (_) {
        return 0;
      }
    }
    return service.unreadCount(gid);
  },
);

final groupUnreadProvider = Provider.autoDispose.family<int, String>(
  (ref, gid) => ref.watch(groupUnreadCountProvider(gid)).value ?? 0,
);

/// Whether this phone has muted a group. Kept with the 1:1 mutes, on the
/// phone only: the server and the other members never learn of it.
final groupMutedProvider = Provider.autoDispose.family<bool, String>((
  ref,
  gid,
) {
  final prefs = ref.watch(appSessionProvider).value?.chatPreferences;
  if (prefs == null) return false;
  final changes = prefs.changes.listen((_) => ref.invalidateSelf());
  ref.onDispose(changes.cancel);
  return prefs.muted.contains(groupChatId(gid));
});

/// Unread group messages for the app icon's badge: muted groups excluded, as
/// muted 1:1 chats are.
final groupsBadgeProvider = Provider.autoDispose<int>((ref) {
  var total = 0;
  for (final gid in (ref.watch(groupsProvider).value ?? const {}).keys) {
    if (!ref.watch(groupMutedProvider(gid))) {
      total += ref.watch(groupUnreadProvider(gid));
    }
  }
  return total;
});

/// Mutes or unmutes a group on this phone.
Future<void> setGroupMuted(WidgetRef ref, String gid, bool muted) async {
  await ref
      .read(appSessionProvider)
      .value
      ?.chatPreferences
      .mute(groupChatId(gid), muted);
}

/// Shares a new primary colour with every group when it changes in Settings.
final groupColorSyncProvider = Provider<void>((ref) {
  ref.listen(chatBubbleColorsProvider, (before, after) {
    final service = ref.read(groupServiceProvider);
    if (service == null || before?.outgoing == after.outgoing) return;
    service.ownColor = after.outgoing.name;
    unawaited(service.shareColor());
  });
});

/// People this account can put in a group: accepted 1:1 chats, not blocked.
/// The server checks the same thing for every invitation.
final groupContactsProvider = Provider.autoDispose<List<String>>((ref) {
  final chats = ref.watch(chatsProvider).value ?? const [];
  final blocked = ref.watch(blockedUidsProvider).value ?? const <String>{};
  return [
    for (final c in chats)
      if (c.accepted && !blocked.contains(c.peerUid)) c.peerUid,
  ];
});
