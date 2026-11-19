import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/passphrase_lock_providers.dart';
import 'package:fireplace/src/model/lock/passphrase_lock.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/view/lock/set_passphrase_screen.dart';
import 'package:fireplace/src/widgets/app_bar.dart';
import 'package:fireplace/src/widgets/dialog.dart';
import 'package:fireplace/src/widgets/page.dart';
import 'package:fireplace/src/widgets/settings_section.dart';
import 'package:fireplace/src/widgets/status.dart';

/// Settings → Passphrase lock (decision 0033).
class PassphraseLockScreen extends ConsumerStatefulWidget {
  const PassphraseLockScreen({super.key});
  @override
  ConsumerState<PassphraseLockScreen> createState() =>
      _PassphraseLockScreenState();
}

class _PassphraseLockScreenState extends ConsumerState<PassphraseLockScreen> {
  bool _busy = false;
  String? _error;

  PassphraseLockController get _lock =>
      ref.read(passphraseLockProvider.notifier);

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
        setState(() => _error = 'That did not finish. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _notice(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _turnOn() async {
    final on = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const SetPassphraseScreen()),
    );
    if (on == true && mounted) _notice('The passphrase lock is on.');
  }

  Future<void> _chooseAutoLock(AutoLock current) async {
    final picked = await Navigator.of(context).push<AutoLock>(
      MaterialPageRoute(builder: (_) => AutoLockScreen(selected: current)),
    );
    if (picked != null && picked != current) {
      await _run(() => _lock.setAutoLock(picked));
    }
  }

  Future<void> _change() async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => const _ChangePassphraseDialog(),
    );
    if (changed == true && mounted) _notice('Passphrase changed.');
  }

  Future<void> _turnOff() async {
    final passphrase = await showDialog<String>(
      context: context,
      builder: (_) => const _AskPassphraseDialog(
        title: 'Turn off the passphrase lock?',
        message:
            'Your messages and keys on this phone go back to being protected '
            'by the phone’s own lock alone. Notification previews come back '
            'as you had them.',
        action: 'Turn off',
      ),
    );
    if (passphrase == null || !mounted) return;
    await _run(() async {
      if (!await _lock.verify(passphrase)) {
        if (mounted) {
          setState(() => _error = 'That is not the passphrase.');
        }
        return;
      }
      await _lock.disable();
      if (mounted) _notice('The passphrase lock is off.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final state =
        ref.watch(passphraseLockProvider).value ?? PassphraseLockState.off;
    final t = FireplaceUiTokens.of(context);
    return Scaffold(
      appBar: UiAppBar(context: context, title: const Text('Passphrase lock')),
      body: UiPageScroll(
        children: [
          if (_error != null)
            UiActionError(key: const Key('lockError'), message: _error!),
          if (_busy) const LinearProgressIndicator(),
          if (!state.on) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 8, 4, 12),
              child: Text(
                'Lock Fireplace with a passphrase of your own. Your messages '
                'and keys on this phone are then sealed with it, and '
                'Fireplace asks for it each time it opens.',
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
              child: Text(
                'While it is on, notifications say “New Message”, without '
                'the text or who it is from.',
              ),
            ),
            const UiNotice(
              warning: true,
              text:
                  'If you forget the passphrase, nobody can open this phone’s '
                  'messages. They can only be erased, and this phone set up '
                  'again with your recovery key.',
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('setUpLock'),
              onPressed: _busy ? null : _turnOn,
              child: const Text('Set a passphrase'),
            ),
          ] else
            UiSettingsSection(
              title: 'On',
              children: [
                ListTile(
                  key: const Key('lockNow'),
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('Lock now'),
                  enabled: !_busy,
                  onTap: () => _run(_lock.lockNow),
                ),
                ListTile(
                  key: const Key('autoLock'),
                  leading: const Icon(Icons.timer_outlined),
                  title: const Text('Lock when away'),
                  subtitle: Text(state.autoLock.label),
                  trailing: const Icon(Icons.chevron_right),
                  enabled: !_busy,
                  onTap: () => _chooseAutoLock(state.autoLock),
                ),
                ListTile(
                  key: const Key('changePassphrase'),
                  leading: const Icon(Icons.password),
                  title: const Text('Change passphrase'),
                  enabled: !_busy,
                  onTap: _change,
                ),
                ListTile(
                  key: const Key('turnOffLock'),
                  leading: Icon(Icons.lock_open_outlined, color: t.danger),
                  title: Text('Turn off', style: TextStyle(color: t.danger)),
                  enabled: !_busy,
                  onTap: _turnOff,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// How long the app may be away before it locks itself.
class AutoLockScreen extends StatelessWidget {
  const AutoLockScreen({super.key, required this.selected});
  final AutoLock selected;

  @override
  Widget build(BuildContext context) {
    final t = FireplaceUiTokens.of(context);
    return Scaffold(
      appBar: UiAppBar(context: context, title: const Text('Lock when away')),
      body: UiPageScroll(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 8, 4, 20),
            child: Text(
              'Once Fireplace has been in the background this long, it asks '
              'for the passphrase again.',
            ),
          ),
          UiSettingsSection(
            title: 'Lock',
            children: [
              for (final choice in AutoLock.values)
                ListTile(
                  key: Key('autoLock_${choice.name}'),
                  title: Text(choice.label),
                  trailing: choice == selected
                      ? Icon(Icons.check_rounded, color: t.accent)
                      : null,
                  onTap: () => Navigator.of(context).pop(choice),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Asks for the passphrase before an action that needs it. Pops with it.
class _AskPassphraseDialog extends StatefulWidget {
  const _AskPassphraseDialog({
    required this.title,
    required this.message,
    required this.action,
  });
  final String title, message, action;
  @override
  State<_AskPassphraseDialog> createState() => _AskPassphraseDialogState();
}

class _AskPassphraseDialogState extends State<_AskPassphraseDialog> {
  final _passphrase = TextEditingController();

  @override
  void dispose() {
    _passphrase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UiDialog(
    title: Text(widget.title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.message),
        const SizedBox(height: 12),
        TextField(
          key: const Key('confirmPassphrase'),
          controller: _passphrase,
          obscureText: true,
          autofocus: true,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Passphrase'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        key: const Key('confirmPassphraseAction'),
        onPressed: _passphrase.text.isEmpty
            ? null
            : () => Navigator.pop(context, _passphrase.text),
        child: Text(widget.action),
      ),
    ],
  );
}

/// The current passphrase and a new one, twice. Pops true once changed.
class _ChangePassphraseDialog extends ConsumerStatefulWidget {
  const _ChangePassphraseDialog();
  @override
  ConsumerState<_ChangePassphraseDialog> createState() =>
      _ChangePassphraseDialogState();
}

class _ChangePassphraseDialogState
    extends ConsumerState<_ChangePassphraseDialog> {
  final _current = TextEditingController(),
      _next = TextEditingController(),
      _again = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_next.text.length < PassphraseLock.minimumLength) {
      setState(
        () =>
            _error = 'Use at least ${PassphraseLock.minimumLength} characters.',
      );
      return;
    }
    if (_next.text != _again.text) {
      setState(() => _error = 'The two new passphrases differ.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final changed = await ref
          .read(passphraseLockProvider.notifier)
          .change(_current.text, _next.text);
      if (!mounted) return;
      if (changed) {
        Navigator.pop(context, true);
      } else {
        setState(() {
          _busy = false;
          _error = 'The current passphrase is not right.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'The passphrase was not changed. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => UiDialog(
    title: const Text('Change passphrase'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PassphraseField(
          key: const Key('currentPassphrase'),
          controller: _current,
          label: 'Current passphrase',
          enabled: !_busy,
          onChanged: () => setState(() => _error = null),
        ),
        const SizedBox(height: 8),
        _PassphraseField(
          key: const Key('nextPassphrase'),
          controller: _next,
          label: 'New passphrase',
          enabled: !_busy,
          onChanged: () => setState(() => _error = null),
        ),
        const SizedBox(height: 8),
        _PassphraseField(
          key: const Key('againPassphrase'),
          controller: _again,
          label: 'Repeat new passphrase',
          enabled: !_busy,
          onChanged: () => setState(() => _error = null),
        ),
        if (_error != null) UiActionError(message: _error!),
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        key: const Key('saveNewPassphrase'),
        onPressed:
            _busy ||
                _current.text.isEmpty ||
                _next.text.isEmpty ||
                _again.text.isEmpty
            ? null
            : _save,
        child: const Text('Change'),
      ),
    ],
  );
}

/// A hidden field for a passphrase: no suggestions, no autocorrect.
class _PassphraseField extends StatelessWidget {
  const _PassphraseField({
    super.key,
    required this.controller,
    required this.label,
    required this.enabled,
    required this.onChanged,
  });
  final TextEditingController controller;
  final String label;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    enabled: enabled,
    obscureText: true,
    autocorrect: false,
    enableSuggestions: false,
    onChanged: (_) => onChanged(),
    decoration: InputDecoration(labelText: label),
  );
}
