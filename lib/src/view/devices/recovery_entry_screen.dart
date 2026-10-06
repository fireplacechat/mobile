import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/styles/brand/lockup.dart';
import 'package:fireplace/src/model/keys/recovery_service.dart';
import 'package:fireplace/src/widgets/app_bar.dart';
import 'package:fireplace/src/widgets/page.dart';

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
