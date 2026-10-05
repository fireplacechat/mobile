import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import 'presentation.dart';
import 'safety_ui.dart';
import 'verify_screen.dart';

class ChatDetailsScreen extends ConsumerStatefulWidget {
  const ChatDetailsScreen({
    super.key,
    required this.peerUid,
    required this.chatId,
    required this.name,
    required this.onBlock,
    required this.onUnblock,
  });
  final String peerUid, chatId, name;
  final Future<void> Function() onBlock, onUnblock;
  @override
  ConsumerState<ChatDetailsScreen> createState() => _ChatDetailsScreenState();
}

class _ChatDetailsScreenState extends ConsumerState<ChatDetailsScreen> {
  bool _busy = false;
  String? _error;
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not update this contact. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final verified = ref.watch(peerVerifiedProvider(w.peerUid)).value == true;
    final blocked =
        ref.watch(blockedUidsProvider).value?.contains(w.peerUid) == true;
    return Scaffold(
      appBar: UiAppBar(context: context, title: const Text('Chat details')),
      body: UiPageScroll(
        children: [
          Center(child: PersonAvatar(name: w.name, size: 72)),
          const SizedBox(height: 12),
          Text(
            '@${w.name}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 24),
          UiSettingsSection(
            title: 'Privacy and safety',
            children: [
              ListTile(
                key: const Key('detailsVerify'),
                leading: Icon(
                  verified ? Icons.verified_user : Icons.shield_outlined,
                ),
                title: const Text('Security code'),
                subtitle: Text(verified ? 'Verified' : 'Not verified yet'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _busy
                    ? null
                    : () => _run(() async {
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => VerifyScreen(
                              peerUid: w.peerUid,
                              peerName: w.name,
                            ),
                          ),
                        );
                      }),
              ),
              ListTile(
                key: const Key('detailsBlock'),
                leading: const Icon(Icons.block),
                title: Text(blocked ? 'Unblock' : 'Block'),
                subtitle: Text(
                  blocked
                      ? 'Allow messages from this person again'
                      : 'Stop new chats and messages from this person',
                ),
                onTap: _busy
                    ? null
                    : () => _run(blocked ? w.onUnblock : w.onBlock),
              ),
              ListTile(
                key: const Key('detailsReport'),
                leading: const Icon(Icons.flag_outlined),
                title: const Text('Report'),
                subtitle: const Text(
                  'Message context is optional and starts off',
                ),
                onTap: _busy
                    ? null
                    : () => _run(() async {
                        await showReportDialog(
                          context,
                          ref,
                          peerUid: w.peerUid,
                          name: w.name,
                          chatId: w.chatId,
                        );
                      }),
              ),
            ],
          ),
          if (_busy)
            const LinearProgressIndicator(
              semanticsLabel: 'Completing contact action',
            ),
          if (_error != null) UiActionError(message: _error!),
        ],
      ),
    );
  }
}
