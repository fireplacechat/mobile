import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/chat_color_preference.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/model/groups/group_models.dart';
import 'package:fireplace/src/model/groups/group_service.dart';

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
