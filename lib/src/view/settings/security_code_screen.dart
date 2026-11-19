import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/fireplace_crypto.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/widgets/app_bar.dart';
import 'package:fireplace/src/widgets/page.dart';

/// Settings → Security code: this account's identity fingerprint, with what
/// it is for (issue 202). It used to be a row of hex in Settings itself.
class SecurityCodeScreen extends ConsumerStatefulWidget {
  const SecurityCodeScreen({super.key});
  @override
  ConsumerState<SecurityCodeScreen> createState() => _SecurityCodeScreenState();
}

class _SecurityCodeScreenState extends ConsumerState<SecurityCodeScreen> {
  Future<String>? _code;
  String? _codeFor;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appSessionProvider).value;
    final t = FireplaceUiTokens.of(context);
    if (s != null && _codeFor != s.uid) {
      _codeFor = s.uid;
      _code = identityFingerprint(s.device.identity.publicBytes);
    }
    return Scaffold(
      appBar: UiAppBar(context: context, title: const Text('Security code')),
      body: UiPageScroll(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'This code belongs to your account’s encryption key. It changes '
            'only if you start fresh without a recovery key, and then your '
            'contacts are told.',
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: t.panel,
              borderRadius: BorderRadius.circular(16),
            ),
            child: FutureBuilder<String>(
              future: _code,
              builder: (_, snap) => SelectableText(
                snap.data ?? '…',
                key: const Key('ownSecurityCode'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  height: 1.6,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'To check a contact, open your chat with them and tap the shield '
            'at the top.',
            style: TextStyle(color: t.secondaryText),
          ),
        ],
      ),
    );
  }
}
