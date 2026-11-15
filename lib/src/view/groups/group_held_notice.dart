import 'package:fireplace/src/app/group_providers.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/view/chat/review_chat_identity.dart';
import 'package:fireplace/src/widgets/status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shown in a group while a member's changed security code is holding it up
/// (decision 0061). Reviewing it is the same step as in a chat with them.
class GroupHeldNotice extends ConsumerStatefulWidget {
  const GroupHeldNotice({super.key, required this.gid});
  final String gid;
  @override
  ConsumerState<GroupHeldNotice> createState() => _GroupHeldNoticeState();
}

class _GroupHeldNoticeState extends ConsumerState<GroupHeldNotice> {
  bool _busy = false;

  Future<void> _review(String peerUid, List<int> newIdentityPub) async {
    final session = ref.read(appSessionProvider).value;
    if (session == null || _busy) return;
    setState(() => _busy = true);
    try {
      await reviewChatIdentity(
        context,
        session,
        peerUid,
        newIdentityPub,
        isMounted: () => mounted,
        notice: (text) {
          if (!mounted) return;
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(text)));
        },
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final held = ref.watch(groupHeldProvider).value?[widget.gid];
    if (held == null) return const SizedBox.shrink();
    final name = ref.watch(peerUsernameProvider(held.peerUid)).value ?? '…';
    return UiNotice(
      key: const Key('groupHeldNotice'),
      warning: true,
      text: '$name’s security code changed. This group is on hold.',
      actions: [
        TextButton(
          key: const Key('reviewGroupIdentity'),
          onPressed: _busy
              ? null
              : () => _review(held.peerUid, held.newIdentityPub),
          child: Text(_busy ? 'Reviewing…' : 'Review'),
        ),
      ],
    );
  }
}
