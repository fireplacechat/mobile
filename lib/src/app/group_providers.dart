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

/// Whether this session offers groups (a build with FIREPLACE_GROUPS whose
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
/// Counted here from the local history, like 1:1 chats: the server holds no
/// read state and nobody is told what was read.
final groupUnreadProvider = Provider.autoDispose.family<int, String>((
  ref,
  gid,
) {
  final prefs = ref.watch(appSessionProvider).value?.chatPreferences;
  if (prefs == null || !prefs.available) return 0;
  final changes = prefs.changes.listen((_) => ref.invalidateSelf());
  ref.onDispose(changes.cancel);
  final id = groupChatId(gid);
  final incoming = [
    for (final m
        in ref.watch(groupMessagesProvider(gid)).value ??
            const <LocalMessage>[])
      if (!m.outgoing &&
          m.visible &&
          !m.remotelyDeleted &&
          m.status == MessageStatus.ok)
        m.id,
  ];
  if (prefs.needsBaseline(id)) {
    // What is already here when the group first appears is not "new".
    unawaited(prefs.seedExisting(id, incoming).catchError((Object _) {}));
    return 0;
  }
  final seen = prefs.seen[id] ?? const <String>{};
  return incoming.where((m) => !seen.contains(m)).length;
});

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
