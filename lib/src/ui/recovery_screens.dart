import 'package:flutter/material.dart';

import 'presentation.dart';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../services/auth_service.dart';
import '../services/recovery_service.dart';
import 'qr_scan_page.dart';
import 'logo.dart';
import 'design_tokens.dart';

/// Create or replace the recovery key. The key is shown once and never stored.
class RecoveryKeyScreen extends ConsumerStatefulWidget {
  const RecoveryKeyScreen({super.key});
  @override
  ConsumerState<RecoveryKeyScreen> createState() => _RecoveryKeyScreenState();
}

class _RecoveryKeyScreenState extends ConsumerState<RecoveryKeyScreen> {
  String? _shown;
  bool _saved = false;
  bool _allowLeave = false, _leaving = false;
  bool _busy = false;
  String? _error;
  bool _copying = false;
  String? _copyError;

  Future<void> _copyKey() async {
    if (_copying || _shown == null) return;
    setState(() {
      _copying = true;
      _copyError = null;
    });
    try {
      await Clipboard.setData(ClipboardData(text: _shown!));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Recovery key copied')));
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _copyError =
              'Could not copy the key. Try again, or write it down.',
        );
      }
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  Future<void> _create() async {
    if (_busy) return;
    final s = ref.read(appSessionProvider).value;
    if (s == null) {
      setState(() => _error = 'Your account is not ready. Try again.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (ref.read(hasBackupProvider).value == true) {
        final replace = await showDialog<bool>(
          context: context,
          builder: (ctx) => UiDialog(
            title: const Text('Replace your recovery key?'),
            content: const SingleChildScrollView(
              child: Text(
                'Your old recovery key will stop working. Save the new key before leaving this screen.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                key: const Key('confirmReplaceRecovery'),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Replace key'),
              ),
            ],
          ),
        );
        if (replace != true || !mounted) return;
      }
      final key = await ref
          .read(recoveryServiceProvider)
          .createBackup(s.uid, s.device.identity);
      final text = await key.display();
      if (mounted) setState(() => _shown = text);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not create a recovery key. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmLeave() async {
    if (_busy || _leaving || !mounted) return;
    _leaving = true;
    try {
      final leave = await showDialog<bool>(
        context: context,
        builder: (ctx) => UiDialog(
          title: const Text('Have you saved your recovery key?'),
          content: const SingleChildScrollView(
            child: Text(
              'This key cannot be shown again after you leave. Save it before closing this screen.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep it open'),
            ),
            TextButton(
              key: const Key('leaveRecovery'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Leave without saving'),
            ),
          ],
        ),
      );
      if (leave == true && mounted) {
        setState(() => _allowLeave = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop();
        });
      }
    } finally {
      _leaving = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final backup = ref.watch(hasBackupProvider);
    final has = backup.value ?? false;
    return PopScope(
      canPop: !_busy && (_shown == null || _saved || _allowLeave),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _shown != null) _confirmLeave();
      },
      child: Scaffold(
        appBar: UiAppBar(context: context, title: Text('Recovery key')),
        body: UiPageScroll(
          padding: EdgeInsets.all(20),
          children: [
            Text(
              'Your messages are encrypted with keys that live on your devices. If '
              'you lose every device, only a recovery key can restore your account '
              'identity on a new phone. Past messages are not backed up; only your '
              'ability to keep your identity and contacts’ trust.',
            ),
            SizedBox(height: 16),
            if (_shown == null) ...[
              if (backup.isLoading)
                const LinearProgressIndicator(
                  semanticsLabel: 'Checking recovery key',
                ),
              if (backup.hasError)
                UiActionError(
                  message: 'Could not check your recovery key. Try again.',
                ),
              if (backup.hasError)
                TextButton(
                  onPressed: () => ref.invalidate(hasBackupProvider),
                  child: const Text('Try again'),
                ),
              if (backup.hasValue)
                UiStatus(
                  label: has ? 'A recovery key exists' : 'No recovery key yet',
                  icon: has ? Icons.check_circle_outline : Icons.key_outlined,
                ),
              SizedBox(height: 16),
              FilledButton(
                key: Key('createRecovery'),
                onPressed: _busy || !backup.hasValue ? null : _create,
                child: Text(
                  _busy
                      ? 'Creating…'
                      : has
                      ? 'Replace recovery key'
                      : 'Create recovery key',
                ),
              ),
              if (has)
                Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Replacing it makes the old key stop working.'),
                ),
            ] else ...[
              Text(
                'Write this down or store it in a password manager. We cannot show '
                'it again, and anyone who has it plus your password can take over '
                'your encryption identity.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: SelectableText(
                  _shown!,
                  key: Key('recoveryKeyText'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              TextButton.icon(
                key: const Key('copyRecoveryKey'),
                onPressed: _copying ? null : _copyKey,
                icon: Icon(Icons.copy),
                label: Text(_copying ? 'Copying…' : 'Copy'),
              ),
              if (_copyError != null) UiActionError(message: _copyError!),
              const Text(
                'Other apps or synced devices may be able to read your clipboard. '
                'After saving the key, clear your clipboard or copy something else.',
              ),
              CheckboxListTile(
                key: Key('savedCheck'),
                value: _saved,
                onChanged: (v) => setState(() => _saved = v ?? false),
                title: Text('I have saved my recovery key'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              FilledButton(
                key: Key('recoveryDone'),
                onPressed: _saved
                    ? () {
                        ref.invalidate(hasBackupProvider);
                        Navigator.of(context).pop();
                      }
                    : null,
                child: Text('Done'),
              ),
            ],
            if (_error != null) UiActionError(message: _error!),
          ],
        ),
      ),
    );
  }
}

/// Existing-device side of linking: scan the new device's QR, then show the code.
class LinkNewDeviceScreen extends ConsumerStatefulWidget {
  const LinkNewDeviceScreen({super.key, this.scanCode});
  final Future<String?> Function(BuildContext)? scanCode;
  @override
  ConsumerState<LinkNewDeviceScreen> createState() =>
      _LinkNewDeviceScreenState();
}

class _LinkNewDeviceScreenState extends ConsumerState<LinkNewDeviceScreen> {
  final _scroll = ScrollController();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  String? _code;
  String? _error;
  bool _busy = false;

  Future<void> _scan() async {
    if (_busy) return;
    final s = ref.read(appSessionProvider).value;
    if (s == null) {
      setState(() => _error = 'Your account is not ready. Try again.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final raw = widget.scanCode != null
          ? await widget.scanCode!(context)
          : await Navigator.of(context).push<String>(
              MaterialPageRoute(
                builder: (_) => const QrScanPage(title: 'Scan the new device'),
              ),
            );
      if (raw == null || !mounted) return;
      final code = await ref
          .read(recoveryServiceProvider)
          .approveLink(s.uid, s.device.identity, raw);
      if (mounted) {
        setState(() => _code = code);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
        });
      }
    } on RecoveryException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not approve the link. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: UiAppBar(context: context),
    body: UiPageScroll(
      controller: _scroll,
      maxWidth: 520,
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
      children: [
        const Center(
          child: Icon(
            Icons.add_to_home_screen_rounded,
            size: 56,
            color: fireplaceOrange,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Link a new device',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 12),
        Text(
          'Keep your identity. Add a device you trust.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 24),
        if (_code == null) ...[
          const _LinkStep(
            number: '1',
            title: 'Sign in on the new device',
            text: 'Use your existing username and password.',
          ),
          const _LinkStep(
            number: '2',
            title: 'Show its QR code',
            text: 'Choose “Link with your other device” on the new device.',
          ),
          const _LinkStep(
            number: '3',
            title: 'Scan and confirm',
            text: 'Scan that QR code here, then enter the confirmation code on the new device.',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('scanLink'),
            onPressed: _busy ? null : _scan,
            icon: const Icon(Icons.qr_code_scanner),
            label: Text(_busy ? 'Linking…' : 'Scan the new device'),
          ),
          const SizedBox(height: 16),
          const Text(
            'Only link a device you hold in your hands. Past messages stay on the devices that received them.',
            textAlign: TextAlign.center,
          ),
        ] else ...[
          const Text(
            'Type this code on the new device to finish:',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SelectableText(
                _code!,
                textAlign: TextAlign.center,
                key: const Key('approveCode'),
                style: Theme.of(context).textTheme.headlineLarge
                    ?.copyWith(letterSpacing: 3, fontFamily: 'monospace'),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'If the new device does not ask for a code, or you did not start this, do not continue: remove it from Settings → Your devices.',
            textAlign: TextAlign.center,
          ),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: UiActionError(message: _error!),
          ),
      ],
    ),
  );
}

class _LinkStep extends StatelessWidget {
  const _LinkStep({
    required this.number,
    required this.title,
    required this.text,
  });
  final String number, title, text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: FireplaceUiTokens.of(context).selectedRow,
              child: Text(
                number,
                style: TextStyle(
                  color: FireplaceUiTokens.of(context).accentText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              text,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> showChangePasswordDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final service = ref.read(authServiceProvider);
  final changed = await showDialog<bool>(
    context: context,
    builder: (_) => _ChangePasswordDialog(service: service),
  );
  if (changed == true && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Password changed.')));
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({required this.service});
  final AuthService service;
  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _cur = TextEditingController(), _next = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _cur.dispose();
    _next.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_cur.text.isEmpty ||
        _next.text.length < AuthService.minPasswordLength) {
      setState(
        () => _error = 'Enter your current password and a new password with at least 8 characters.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.changePassword(
        currentPassword: _cur.text,
        newPassword: _next.text,
      );
      if (mounted) Navigator.pop(context, true);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not change your password. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: UiDialog(
      title: const Text('Change password'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('curPw'),
              controller: _cur,
              enabled: !_busy,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(labelText: 'Current password'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('newPw'),
              controller: _next,
              enabled: !_busy,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'New password',
                helperText: 'At least 8 characters',
              ),
              onSubmitted: (_) => _save(),
            ),
            if (_error != null)
              UiActionError(key: const Key('passwordError'), message: _error!),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('pwSave'),
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Saving…' : 'Save'),
        ),
      ],
    ),
  );
}
