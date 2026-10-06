import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/styles/brand/logo.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/widgets/dialog.dart';
import 'package:fireplace/src/widgets/status.dart';
import 'package:fireplace/src/view/devices/link_wait_screen.dart';
import 'package:fireplace/src/view/devices/recovery_entry_screen.dart';

/// Shown when the account already has devices but this install has no keys.
class NewDeviceScreen extends ConsumerStatefulWidget {
  const NewDeviceScreen({super.key, required this.uid});
  final String uid;

  @override
  ConsumerState<NewDeviceScreen> createState() => _NewDeviceScreenState();
}

class _NewDeviceScreenState extends ConsumerState<NewDeviceScreen> {
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
        setState(
          () => _error = 'That action did not finish. Try again, or sign out.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(Widget page) => _run(() async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => page));
  });
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  FireplaceLogo(size: 72),
                  SizedBox(height: 12),
                  Text(
                    'Set up this device',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Your account already uses end-to-end encryption on another '
                    'device. To read and send messages here, prove it is you.',
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 24),
                  if (_error != null) UiActionError(message: _error!),
                  _Option(
                    key: Key('optLink'),
                    icon: Icons.qr_code_2,
                    title: 'Link with your other device',
                    subtitle: 'Show a QR code and scan it from a device you already use.',
                    onTap: _busy
                        ? null
                        : () => _open(LinkWaitScreen(uid: widget.uid)),
                  ),
                  _Option(
                    key: Key('optRecovery'),
                    icon: Icons.key,
                    title: 'Use your recovery key',
                    subtitle: 'The 36-character key you saved when you set up backup.',
                    onTap: _busy
                        ? null
                        : () => _open(RecoveryEntryScreen(uid: widget.uid)),
                  ),
                  _Option(
                    key: Key('optReset'),
                    icon: Icons.warning_amber_rounded,
                    iconColor: FireplaceUiTokens.of(context).danger,
                    title: 'I lost everything: start fresh',
                    subtitle:
                        'Creates a new identity. Your contacts will see a security-code '
                        'change. Old messages stay unreadable.',
                    onTap: _busy
                        ? null
                        : () => _run(() => _confirmReset(context, ref)),
                  ),
                  SizedBox(height: 12),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(
                            () => ref.read(authServiceProvider).signOut(),
                          ),
                    child: Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => UiDialog(
        icon: Icon(
          Icons.warning_amber_rounded,
          color: FireplaceUiTokens.of(context).danger,
          size: 40,
        ),
        title: Text('Start fresh?'),
        content: Text(
          'This removes your other devices and recovery key from your account '
          'and creates a new encryption identity. Contacts will be warned that '
          'your security code changed. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel'),
          ),
          TextButton(
            key: Key('confirmReset'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Start fresh',
              style: TextStyle(color: FireplaceUiTokens.of(context).danger),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(recoveryServiceProvider).resetIdentity(widget.uid);
      if (mounted) ref.invalidate(appSessionProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not finish setting up your new identity. Try again, or sign out.',
            ),
          ),
        );
      }
    }
  }
}

class _Option extends StatelessWidget {
  const _Option({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor,
  });
  final IconData icon;
  final String title, subtitle;
  final VoidCallback? onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.only(bottom: 10),
    child: ListTile(
      leading: Icon(
        icon,
        color: iconColor ?? FireplaceUiTokens.of(context).accent,
        size: 30,
      ),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      trailing: Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}
