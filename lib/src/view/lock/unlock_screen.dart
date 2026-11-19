import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/passphrase_lock_providers.dart';
import 'package:fireplace/src/styles/brand/logo.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/widgets/dialog.dart';
import 'package:fireplace/src/widgets/status.dart';

/// What the app shows while the passphrase lock is closed (decision 0033).
/// Nothing of the account is open behind it.
class UnlockScreen extends ConsumerStatefulWidget {
  const UnlockScreen({super.key});
  @override
  ConsumerState<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends ConsumerState<UnlockScreen> {
  final _passphrase = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _passphrase.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final passphrase = _passphrase.text;
    if (_busy || passphrase.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    var opened = false;
    try {
      opened = await ref
          .read(passphraseLockProvider.notifier)
          .unlock(passphrase);
      if (!opened && mounted) {
        setState(() => _error = 'That is not the passphrase. Try again.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Fireplace could not unlock. Try again.');
      }
    } finally {
      if (mounted && !opened) {
        setState(() => _busy = false);
        _passphrase.clear();
      }
    }
  }

  Future<void> _forgot() async {
    final erase = await showDialog<bool>(
      context: context,
      builder: (ctx) => UiDialog(
        title: const Text('Erase and set up again?'),
        content: const Text(
          'Without the passphrase, nobody can open the messages and keys on '
          'this phone. Erasing removes them from this phone and signs you '
          'out. Your account stays: sign in again and restore it with your '
          'recovery key, or link this phone from another of your devices.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('confirmEraseLocked'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Erase and sign out',
              style: TextStyle(color: FireplaceUiTokens.of(ctx).danger),
            ),
          ),
        ],
      ),
    );
    if (erase != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(passphraseLockProvider.notifier).eraseAndSignOut();
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'This phone could not be erased. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = FireplaceUiTokens.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: FireplaceLogo(size: 56)),
                  const SizedBox(height: 20),
                  Text(
                    'Fireplace is locked',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter your passphrase to open your messages.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: t.secondaryText),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    key: const Key('unlockPassphrase'),
                    controller: _passphrase,
                    enabled: !_busy,
                    obscureText: true,
                    autofocus: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _unlock(),
                    decoration: const InputDecoration(labelText: 'Passphrase'),
                  ),
                  if (_error != null)
                    UiActionError(
                      key: const Key('unlockError'),
                      message: _error!,
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const Key('unlock'),
                    onPressed: _busy || _passphrase.text.isEmpty
                        ? null
                        : _unlock,
                    child: Text(_busy ? 'Unlocking…' : 'Unlock'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    key: const Key('forgotPassphrase'),
                    onPressed: _busy ? null : _forgot,
                    child: const Text('Forgot your passphrase?'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
