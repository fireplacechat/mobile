import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/widgets/app_bar.dart';
import 'package:fireplace/src/widgets/dialog.dart';
import 'package:fireplace/src/widgets/page.dart';
import 'package:fireplace/src/widgets/status.dart';

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
