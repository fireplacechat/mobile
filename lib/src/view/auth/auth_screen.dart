import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/account/auth_service.dart';
import 'package:fireplace/src/styles/brand/logo.dart';
import 'package:fireplace/src/styles/brand/lockup.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/view/settings/legal_links.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});
  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _invite = TextEditingController();
  bool _signUp = false;
  bool _busy = false;
  bool _legalOpen = false;
  bool _obscure = true;
  // Eligibility self-declaration (16+). Never pre-selected; not a verified age check.
  bool _is16OrOlder = false;
  bool _showAgeError = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _invite.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    // Before any Auth call: sign-up needs the declaration, also for keyboard submission.
    if (_signUp && !_is16OrOlder) {
      setState(() => _showAgeError = true);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = ref.read(authServiceProvider);
    try {
      if (_signUp) {
        await auth.signUp(
          username: _username.text,
          password: _password.text,
          inviteCode: _invite.text,
        );
      } else {
        await auth.signIn(username: _username.text, password: _password.text);
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = _signUp
              ? 'We could not create your account. Please try again.'
              : 'We could not sign you in. Please try again.',
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
      ).push(MaterialPageRoute<void>(builder: (_) => const LegalLinksScreen()));
    } finally {
      if (mounted) setState(() => _legalOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 400),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: FireplaceLogo(size: 72)),
                    SizedBox(height: 12),
                    const Center(child: FireplaceWordmark()),
                    SizedBox(height: 28),
                    Text(
                      _signUp ? 'Join the beta' : 'Welcome back',
                      style: theme.textTheme.titleLarge,
                    ),
                    SizedBox(height: 6),
                    Text(
                      _signUp
                          ? 'Use your invite to get started.'
                          : 'Sign in with your username and password.',
                      style: theme.textTheme.bodySmall,
                    ),
                    SizedBox(height: 20),
                    TextFormField(
                      key: Key('username'),
                      controller: _username,
                      autofillHints: const [AutofillHints.username],
                      autocorrect: false,
                      readOnly:
                          _busy, // frozen while busy; retain focus for retry
                      enableSuggestions: false,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'Username',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (v) => AuthService.isValidUsername(v ?? '')
                          ? null
                          : '3-20 characters: a-z, 0-9, _',
                    ),
                    SizedBox(height: 12),
                    TextFormField(
                      key: Key('password'),
                      controller: _password,
                      readOnly:
                          _busy, // frozen while busy; retain focus for retry
                      enableSuggestions: false,
                      autocorrect: false,
                      obscureText: _obscure,
                      autofillHints: [
                        _signUp
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          tooltip: _obscure ? 'Show password' : 'Hide password',
                          onPressed: _busy
                              ? null
                              : () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) =>
                          (v ?? '').length >= AuthService.minPasswordLength
                          ? null
                          : 'At least ${AuthService.minPasswordLength} characters',
                    ),
                    if (_signUp) ...[
                      SizedBox(height: 12),
                      TextFormField(
                        key: Key('invite'),
                        controller: _invite,
                        readOnly:
                            _busy, // frozen while busy; retain focus for retry
                        autocorrect: false,
                        enableSuggestions: false,
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          labelText: 'Invite code',
                          hintText: 'ABCD-EFGH-JKLM-NPQR',
                          helperText: 'Use the code in your beta invitation.',
                          helperMaxLines: 2,
                          prefixIcon: Icon(Icons.card_giftcard_outlined),
                        ),
                        validator: (v) =>
                            AuthService.normalizeInvite(v ?? '') == null
                            ? 'Enter the 16-character invite code you were given'
                            : null,
                      ),
                    ],
                    if (_signUp) ...[
                      SizedBox(height: 8),
                      CheckboxListTile(
                        key: Key('age16'),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text('I am 16 or older'),
                        value: _is16OrOlder,
                        onChanged: _busy
                            ? null
                            : (v) => setState(() {
                                _is16OrOlder = v == true;
                                _showAgeError = false;
                              }),
                      ),
                      if (_showAgeError)
                        Padding(
                          padding: EdgeInsets.only(left: 12, bottom: 4),
                          child: Text(
                            'You must be 16 or older to join this beta.',
                            key: Key('age16Error'),
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ),
                      Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          'By creating an account you agree to the terms and '
                          'privacy policy.',
                          key: Key('betaNotice'),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton(
                          key: const Key('legalLinks'),
                          onPressed: _busy || _legalOpen ? null : _showLegal,
                          child: const Text(
                            'Read the terms and privacy policy',
                          ),
                        ),
                      ),
                    ],
                    if (_signUp)
                      Padding(
                        padding: EdgeInsets.only(top: 10),
                        child: Text(
                          'There is no email reset. Your password signs you in. '
                          'A recovery key restores your encryption identity, '
                          'not past messages.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    if (_error != null)
                      Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: FireplaceBrandText(
                          _error!,
                          key: Key('authError'),
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    SizedBox(height: 20),
                    FilledButton(
                      key: Key('submit'),
                      onPressed: _busy || (_signUp && !_is16OrOlder)
                          ? null
                          : _submit,
                      child: _busy
                          ? SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.onPrimary,
                                semanticsLabel: _signUp
                                    ? 'Creating account'
                                    : 'Signing in',
                              ),
                            )
                          : Text(_signUp ? 'Create account' : 'Sign in'),
                    ),
                    TextButton(
                      key: Key('toggle'),
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _signUp = !_signUp;
                              _error = null;
                              _is16OrOlder = false;
                              _showAgeError = false;
                            }),
                      child: Text(
                        _signUp
                            ? 'Have an account? Sign in'
                            : 'New here? Create an account',
                        style: TextStyle(
                          color: FireplaceUiTokens.of(context).accentText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
