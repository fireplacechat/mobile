import 'package:flutter/material.dart';

import 'package:fireplace/src/ui/presentation.dart';
import 'package:fireplace/src/styles/brand/lockup.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/crypto/link.dart';
import 'package:fireplace/src/model/keys/recovery_service.dart';
import 'package:fireplace/src/styles/brand/logo.dart';
import 'package:fireplace/src/styles/design_tokens.dart';

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

class RecoveryEntryScreen extends ConsumerStatefulWidget {
  const RecoveryEntryScreen({super.key, required this.uid});
  final String uid;
  @override
  ConsumerState<RecoveryEntryScreen> createState() =>
      _RecoveryEntryScreenState();
}

class _RecoveryEntryScreenState extends ConsumerState<RecoveryEntryScreen> {
  final _c = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (_busy) return;
    final input = _c.text;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(recoveryServiceProvider)
          .restoreWithRecoveryKey(widget.uid, input);
      if (mounted) ref.invalidate(appSessionProvider);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on RecoveryException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not restore your identity. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: UiAppBar(context: context, title: Text('Recovery key')),
    body: UiPageScroll(
      padding: EdgeInsets.all(20),
      children: [
        Text(
          'Enter the recovery key you saved. Dashes and spaces are optional.',
        ),
        SizedBox(height: 16),
        TextField(
          key: Key('recoveryInput'),
          controller: _c,
          enabled: !_busy,
          onSubmitted: (_) => _go(),
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.characters,
          style: TextStyle(fontFamily: 'monospace', fontSize: 16),
          decoration: InputDecoration(hintText: 'XXXX-XXXX-XXXX-…'),
        ),
        if (_error != null)
          Padding(
            padding: EdgeInsets.only(top: 12),
            child: FireplaceBrandText(
              _error!,
              key: Key('recoveryError'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        SizedBox(height: 20),
        FilledButton(
          key: Key('recoverGo'),
          onPressed: _busy ? null : _go,
          child: _busy
              ? SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('Restore'),
        ),
      ],
    ),
  );
}

/// New device side of linking: show the QR, wait, then confirm the 6-digit code.
class LinkWaitScreen extends ConsumerStatefulWidget {
  const LinkWaitScreen({super.key, required this.uid});
  final String uid;
  @override
  ConsumerState<LinkWaitScreen> createState() => _LinkWaitScreenState();
}

class _LinkWaitScreenState extends ConsumerState<LinkWaitScreen> {
  LinkRequest? _req;
  SealedIdentity? _sealed;
  final _code = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _starting = false, _completed = false;
  int _attempt = 0;
  late final RecoveryService _service;

  @override
  void initState() {
    super.initState();
    _service = ref.read(recoveryServiceProvider);
    _start();
  }

  Future<void> _start() async {
    if (_starting || _busy) return;
    final attempt = ++_attempt;
    final old = _req;
    setState(() {
      _starting = true;
      _req = null;
      _sealed = null;
      _error = null;
    });
    try {
      if (old != null) await _service.cancelLink(old);
      if (!mounted) return;
      final req = await _service.startLink(widget.uid);
      if (!mounted || attempt != _attempt) {
        await _service.cancelLink(req);
        return;
      }
      setState(() {
        _req = req;
        _starting = false;
      });
      final sealed = await _service.awaitResponse(req);
      if (mounted && attempt == _attempt) setState(() => _sealed = sealed);
    } on RecoveryException catch (e) {
      if (mounted && attempt == _attempt) setState(() => _error = e.message);
    } catch (_) {
      if (mounted && attempt == _attempt) {
        setState(() => _error = 'Could not link this device. Try again.');
      }
    } finally {
      if (mounted && attempt == _attempt) setState(() => _starting = false);
    }
  }

  @override
  void dispose() {
    _attempt++;
    _code.dispose();
    final req = _req;
    if (req != null && !_completed) _service.cancelLink(req).catchError((_) {});
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_busy || _req == null || _sealed == null) return;
    final code = _code.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(
        () => _error = 'Enter the 6-digit code shown on your other device.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.completeLink(_req!, _sealed!, code);
      _completed = true;
      if (mounted) ref.invalidate(appSessionProvider);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on RecoveryException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = 'Could not finish linking this device. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final req = _req;
    return Scaffold(
      appBar: UiAppBar(context: context, title: Text('Link this device')),
      body: UiPageScroll(
        padding: EdgeInsets.all(20),
        children: [
          if (req == null && _error == null)
            Center(child: CircularProgressIndicator())
          else if (_sealed == null && req != null) ...[
            Text(
              'On your other device open Settings → Link a new device and scan '
              'this code.',
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16),
            Center(
              child: Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: QrImageView(data: req.qrPayload, size: 220),
              ),
            ),
            SizedBox(height: 12),
            if (_error == null) Center(child: Text('Waiting for approval…')),
          ] else if (_sealed != null) ...[
            Text(
              'Your other device is showing a 6-digit code. Type it here to '
              'finish. This makes sure nobody swapped your keys on the way.',
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16),
            TextField(
              key: Key('linkCode'),
              controller: _code,
              enabled: !_busy,
              onSubmitted: (_) => _confirm(),
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                letterSpacing: 2,
                fontFamily: 'monospace',
              ),
            ),
            FilledButton(
              key: Key('linkConfirm'),
              onPressed: _busy ? null : _confirm,
              child: Text('Confirm'),
            ),
          ],
          if (_error != null) UiActionError(message: _error!),
          if (_error != null && _sealed == null)
            TextButton(
              key: const Key('retryLink'),
              onPressed: _starting ? null : _start,
              child: const Text('Try again'),
            ),
        ],
      ),
    );
  }
}
