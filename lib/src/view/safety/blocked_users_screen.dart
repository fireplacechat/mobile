import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/widgets/app_bar.dart';
import 'package:fireplace/src/widgets/page.dart';
import 'package:fireplace/src/widgets/status.dart';

class BlockedUsersScreen extends ConsumerWidget {
  const BlockedUsersScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(blockedUidsProvider);
    return Scaffold(
      appBar: UiAppBar(context: context, title: const Text('Blocked people')),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => UiEmptyState(
          title: 'Could not load blocked people',
          message: 'Try again to see your blocked contacts.',
          action: TextButton(
            onPressed: () => ref.invalidate(blockedUidsProvider),
            child: const Text('Try again'),
          ),
        ),
        data: (blocked) => blocked.isEmpty
            ? const UiEmptyState(
                title: 'No blocked people',
                message: 'You can block someone from their chat or a message request.',
                icon: Icons.block,
              )
            : UiPageScroll(
                children: [for (final uid in blocked) _BlockedTile(uid: uid)],
              ),
      ),
    );
  }
}

class _BlockedTile extends ConsumerStatefulWidget {
  const _BlockedTile({required this.uid});
  final String uid;
  @override
  ConsumerState<_BlockedTile> createState() => _BlockedTileState();
}

class _BlockedTileState extends ConsumerState<_BlockedTile> {
  bool _busy = false;
  String? _error;
  Future<void> _unblock() async {
    final session = ref.read(appSessionProvider).value;
    if (_busy || session == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await session.safety.unblock(widget.uid);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not unblock this person. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = ref.watch(peerUsernameProvider(widget.uid)).value ?? '…';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          key: Key('blocked_${widget.uid}'),
          leading: const Icon(Icons.block),
          title: Text('@$name'),
          subtitle: _busy ? const Text('Unblocking…') : null,
          trailing: TextButton(
            key: Key('unblock_${widget.uid}'),
            onPressed: _busy ? null : _unblock,
            child: const Text('Unblock'),
          ),
        ),
        if (_error != null) UiActionError(message: _error!),
      ],
    );
  }
}
