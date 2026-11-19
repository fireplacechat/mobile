import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/group_providers.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/db/local_messages.dart';

/// Messages picked in a group conversation, as Select does in a 1:1 chat
/// (issue 209). Ids only; nothing is stored.
class GroupSelection {
  GroupSelection({Set<String> ids = const {}, this.deleting = false})
    : ids = Set.unmodifiable(ids);
  final Set<String> ids;
  final bool deleting;
  bool get active => ids.isNotEmpty || deleting;
}

class GroupSelectionController extends Notifier<GroupSelection> {
  GroupSelectionController(this.gid);
  final String gid;

  @override
  GroupSelection build() {
    // A new account, or the group gone from this phone, starts empty.
    ref.watch(appSessionProvider.select((s) => s.value?.uid));
    ref.watch(groupServiceProvider);
    return GroupSelection();
  }

  void toggle(String id) {
    if (state.deleting) return;
    final next = {...state.ids};
    if (!next.remove(id)) next.add(id);
    state = GroupSelection(ids: next);
  }

  void clear() {
    if (!state.deleting) state = GroupSelection();
  }

  /// Deletes [messages]: for everyone when [everyone] is set (only your own
  /// sent messages), otherwise on this phone. Stops at the first failure and
  /// keeps what is left selected; returns whether every one went.
  Future<bool> delete(List<LocalMessage> messages, {required bool everyone}) =>
      _run([for (final m in messages) (m.id, everyone)]);

  /// Delete All: your own sent messages for everyone, the rest on this phone,
  /// as in a 1:1 chat.
  Future<bool> deleteAll(List<LocalMessage> shown) => _run([
    for (final m in shown) (m.id, m.outgoing && m.status == MessageStatus.ok),
  ]);

  Future<bool> _run(List<(String, bool)> targets) async {
    final service = ref.read(groupServiceProvider);
    if (service == null || state.deleting) return false;
    final left = {...state.ids};
    state = GroupSelection(ids: left, deleting: true);
    for (final (id, everyone) in targets) {
      try {
        if (everyone) {
          await service.deleteForEveryone(gid, id);
        } else {
          await service.deleteLocally(gid, id);
        }
      } catch (_) {
        if (ref.mounted) state = GroupSelection(ids: left);
        return false;
      }
      if (!ref.mounted) return false;
      left.remove(id);
      state = GroupSelection(ids: left, deleting: true);
    }
    state = GroupSelection();
    return true;
  }
}

final groupSelectionProvider = NotifierProvider.autoDispose
    .family<GroupSelectionController, GroupSelection, String>(
      GroupSelectionController.new,
    );
