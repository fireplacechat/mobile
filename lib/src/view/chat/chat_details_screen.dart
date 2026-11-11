import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/notifications/chat_activity.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/view/safety/confirm_block.dart';
import 'package:fireplace/src/view/safety/report_spam.dart';
import 'package:fireplace/src/view/safety/verify_screen.dart';
import 'package:fireplace/src/widgets/app_bar.dart';
import 'package:fireplace/src/widgets/avatar.dart';
import 'package:fireplace/src/widgets/page.dart';
import 'package:fireplace/src/widgets/settings_section.dart';
import 'package:fireplace/src/widgets/status.dart';

class ChatDetailsScreen extends ConsumerStatefulWidget {
  const ChatDetailsScreen({
    super.key,
    required this.peerUid,
    required this.chatId,
    required this.name,
    required this.onMute,
    required this.onBlock,
    required this.onUnblock,
    required this.onReportSpam,
  });
  final String peerUid, chatId, name;
  final Future<void> Function(bool muted) onMute;
  final Future<void> Function() onBlock, onUnblock;
  final Future<void> Function(ReportSpamChoice choice) onReportSpam;
  @override
  ConsumerState<ChatDetailsScreen> createState() => _ChatDetailsScreenState();
}

class _ChatDetailsScreenState extends ConsumerState<ChatDetailsScreen> {
  bool _busy = false;
  String? _error;
  Future<void> _run(
    Future<void> Function() action, {
    String failure = 'Could not update this contact. Try again.',
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => _error = failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _block(bool blocked) async {
    if (_busy) return;
    if (!blocked) {
      final ok = await confirmBlock(context, widget.name);
      if (!ok || !mounted) return;
    }
    await _run(blocked ? widget.onUnblock : widget.onBlock);
  }

  Future<void> _report(bool blocked) async {
    if (_busy) return;
    final choice = await confirmReportSpam(context, blocked: blocked);
    if (choice == null || !mounted) return;
    await _run(
      () => widget.onReportSpam(choice),
      failure: 'Could not send the spam report. Try again.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final verified = ref.watch(peerVerifiedProvider(w.peerUid)).value == true;
    final blocked =
        ref.watch(blockedUidsProvider).value?.contains(w.peerUid) == true;
    final muted = ref.watch(chatActivityProvider).muted.contains(w.chatId);
    final outline = Theme.of(context).colorScheme.outline;
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
            ],
          ),
          Card(
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: outline, width: 1.25),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ProfileSafetyAction(
                  buttonKey: const Key('detailsMute'),
                  icon: muted
                      ? Icons.notifications_off_outlined
                      : Icons.notifications_none,
                  label: muted ? 'Unmute' : 'Mute',
                  onPressed: _busy ? null : () => _run(() => w.onMute(!muted)),
                ),
                Divider(height: 1, thickness: 1, color: outline),
                ProfileSafetyAction(
                  buttonKey: const Key('detailsBlock'),
                  icon: Icons.block,
                  label: blocked ? 'Unblock User' : 'Block User',
                  danger: !blocked,
                  onPressed: _busy ? null : () => _block(blocked),
                ),
                Divider(height: 1, thickness: 1, color: outline),
                ProfileSafetyAction(
                  buttonKey: const Key('detailsReport'),
                  icon: Icons.announcement_outlined,
                  label: 'Report Spam',
                  danger: true,
                  onPressed: _busy ? null : () => _report(blocked),
                ),
              ],
            ),
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

/// One profile action, the same row shape Signal uses for Block and Report.
/// Mute uses that shape in the normal text colour, with a bell.
class ProfileSafetyAction extends StatelessWidget {
  const ProfileSafetyAction({
    super.key,
    required this.buttonKey,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.danger = false,
  });
  final Key buttonKey;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = FireplaceUiTokens.of(context);
    final color = danger ? t.danger : t.text;
    return InkWell(
      key: buttonKey,
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 17,
                  height: 1.2,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
