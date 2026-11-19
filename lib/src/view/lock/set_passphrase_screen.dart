import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/passphrase_lock_providers.dart';
import 'package:fireplace/src/model/lock/passphrase_lock.dart';
import 'package:fireplace/src/widgets/app_bar.dart';
import 'package:fireplace/src/widgets/page.dart';
import 'package:fireplace/src/widgets/status.dart';

/// Choosing the passphrase that turns the lock on (decision 0033). Says what
/// a forgotten one costs before it is accepted. Pops true once the lock is on.
class SetPassphraseScreen extends ConsumerStatefulWidget {
  const SetPassphraseScreen({super.key});
  @override
  ConsumerState<SetPassphraseScreen> createState() =>
      _SetPassphraseScreenState();
}

class _SetPassphraseScreenState extends ConsumerState<SetPassphraseScreen> {
  final _first = TextEditingController(), _second = TextEditingController();
  bool _understood = false, _busy = false;
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  String? get _problem {
    if (_first.text.length < PassphraseLock.minimumLength) {
      return 'Use at least ${PassphraseLock.minimumLength} characters.';
    }
    if (_first.text != _second.text) return 'The two passphrases differ.';
    return null;
  }

  bool get _ready =>
      !_busy &&
      _understood &&
      _first.text.isNotEmpty &&
      _second.text.isNotEmpty;

  Future<void> _turnOn() async {
    final problem = _problem;
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(passphraseLockProvider.notifier).enable(_first.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error =
              'The lock could not be turned on. Try again. If it was part '
              'way, Fireplace finishes it the next time it is unlocked.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: UiAppBar(context: context, title: const Text('Set a passphrase')),
      body: UiPageScroll(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 8, 4, 16),
            child: Text(
              'Fireplace will ask for it each time it opens. Choose one you '
              'will remember: a few words are easier than a code.',
            ),
          ),
          TextField(
            key: const Key('newPassphrase'),
            controller: _first,
            enabled: !_busy,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) => setState(() => _error = null),
            decoration: InputDecoration(
              labelText: 'Passphrase',
              helperText: 'At least ${PassphraseLock.minimumLength} characters',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('repeatPassphrase'),
            controller: _second,
            enabled: !_busy,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) => setState(() => _error = null),
            decoration: const InputDecoration(labelText: 'Repeat passphrase'),
          ),
          const SizedBox(height: 16),
          const UiNotice(
            warning: true,
            text:
                'If you forget it, nobody can open the messages on this phone, '
                'not even Fireplace. The only way back is to erase this '
                'phone’s Fireplace data and set it up again with your '
                'recovery key.',
          ),
          CheckboxListTile(
            key: const Key('understoodForgotten'),
            value: _understood,
            onChanged: _busy
                ? null
                : (v) => setState(() => _understood = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text('I understand'),
          ),
          if (_error != null)
            UiActionError(
              key: const Key('setPassphraseError'),
              message: _error!,
            ),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('turnOnLock'),
            onPressed: _ready ? _turnOn : null,
            child: Text(_busy ? 'Turning on…' : 'Turn on the lock'),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Column(
                children: [
                  LinearProgressIndicator(
                    semanticsLabel: 'Turning on the lock',
                  ),
                  SizedBox(height: 8),
                  Text('Sealing your data. This takes a few seconds.'),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
