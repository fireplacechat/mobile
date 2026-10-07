import 'package:flutter/material.dart';

import 'package:fireplace/src/widgets/app_bar.dart';
import 'package:fireplace/src/widgets/page.dart';
import 'package:fireplace/src/widgets/status.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/account/auth_service.dart';
import 'package:fireplace/src/styles/brand/logo.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/view/settings/legal_links.dart';

const _whatIsDeleted = <String>[
  'Your username, profile and sign-in account',
  'Your encryption keys, prekeys and recovery-key backup',
  'Every message you sent, from our servers',
  'Everything saved on this phone: keys, chats and settings',
];

const _whatRemains = <String>[
  'Messages you sent that other people already received stay on their devices.',
  'Reports you filed or that were filed about you are kept to handle abuse.',
  'Your contacts see your account as "Deleted account", and your username can be taken by someone else.',
];

/// Asks for the password and runs the deletion. Used from Settings and,
/// with [resume] set, to finish a deletion that was interrupted.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key, this.resume = false});
  final bool resume;
  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _legalOpen = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  String? get _expectedUsername {
    final s = ref.read(appSessionProvider).value;
    if (s != null) return s.username;
    return null;
  }

  bool get _confirmed {
    if (widget.resume) return _password.text.isNotEmpty;
    final expected = _expectedUsername;
    return _password.text.isNotEmpty &&
        expected != null &&
        _username.text.trim().toLowerCase() == expected;
  }

  Future<void> _delete() async {
    if (_busy || _legalOpen || !_confirmed) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(accountServiceProvider)
          .deleteAccount(password: _password.text);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = 'Deletion did not finish. Your account may already be partly deleted. Try again to complete it.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showLegal() async {
    if (_busy || _legalOpen) return;
    setState(() => _legalOpen = true);
    try {
      await Navigator.of(
        context,
      ).push<void>(MaterialPageRoute(builder: (_) => const LegalLinksScreen()));
    } finally {
      if (mounted) setState(() => _legalOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: UiAppBar(
        context: context,
        title: Text(widget.resume ? 'Finish deleting' : 'Delete account'),
      ),
      body: UiPageScroll(
        padding: EdgeInsets.all(20),
        children: [
          if (widget.resume) ...[
            Center(child: FireplaceLogo(size: 64)),
            SizedBox(height: 12),
            Text(
              'Your account was being deleted but the process did not '
              'finish. Enter your password to complete it.',
            ),
            SizedBox(height: 16),
          ] else ...[
            Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: FireplaceUiTokens.of(context).danger,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This permanently deletes your account. It cannot be undone.',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
          ],
          Text('What gets deleted', style: theme.textTheme.titleSmall),
          for (final t in _whatIsDeleted)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.delete_outline, size: 20),
              title: Text(t),
            ),
          SizedBox(height: 8),
          Text('What stays', style: theme.textTheme.titleSmall),
          for (final t in _whatRemains)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.info_outline, size: 20),
              title: Text(t),
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              key: const Key('deletionLegalLinks'),
              onPressed: _busy || _legalOpen ? null : _showLegal,
              child: const Text('Privacy policy and retention details'),
            ),
          ),
          SizedBox(height: 16),
          if (!widget.resume)
            Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: TextField(
                key: Key('confirmUsername'),
                controller: _username,
                enabled: !_busy,
                autocorrect: false,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Confirm username',
                  helperText: 'Type ${_expectedUsername ?? ''} to confirm',
                  helperMaxLines: 3,
                ),
              ),
            ),
          TextField(
            key: Key('confirmPassword'),
            controller: _password,
            enabled: !_busy,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            onSubmitted: (_) => _delete(),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: 'Password'),
          ),
          if (_error != null)
            UiActionError(key: const Key('deleteError'), message: _error!),
          SizedBox(height: 20),
          FilledButton(
            key: Key('deleteAccount'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: _confirmed && !_busy && !_legalOpen ? _delete : null,
            child: _busy
                ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.onError,
                    ),
                  )
                : Text('Delete my account'),
          ),
          if (widget.resume)
            TextButton(
              onPressed: _busy
                  ? null
                  : () => ref.read(authServiceProvider).signOut(),
              child: Text('Sign out instead'),
            ),
        ],
      ),
    );
  }
}
