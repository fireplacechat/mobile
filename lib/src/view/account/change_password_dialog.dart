import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/account/auth_service.dart';
import 'package:fireplace/src/widgets/dialog.dart';
import 'package:fireplace/src/widgets/status.dart';

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
