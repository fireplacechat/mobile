import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/model/common/external_browser.dart';
import 'package:fireplace/src/view/settings/browser_error_dialog.dart';
import 'package:fireplace/src/widgets/app_bar.dart';
import 'package:fireplace/src/widgets/page.dart';

const privacyPolicyUrl = 'https://fireplacechat.com/privacy/';
const termsOfUseUrl = 'https://fireplacechat.com/terms/';

class LegalLinksScreen extends ConsumerStatefulWidget {
  const LegalLinksScreen({super.key});

  @override
  ConsumerState<LegalLinksScreen> createState() => _LegalLinksScreenState();
}

class _LegalLinksScreenState extends ConsumerState<LegalLinksScreen> {
  bool _opening = false;

  Future<void> _open(String address) async {
    if (_opening) return;
    setState(() => _opening = true);
    var opened = false;
    try {
      opened = await ref.read(externalBrowserProvider).open(Uri.parse(address));
    } catch (_) {
      // The page remains usable when the OS refuses or has no browser.
    }
    if (!mounted) return;
    if (!opened) await showBrowserErrorDialog(context);
    if (mounted) setState(() => _opening = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: UiAppBar(context: context, title: const Text('Privacy and terms')),
    body: UiPageScroll(
      children: [
        OutlinedButton.icon(
          key: const Key('openPrivacyPolicy'),
          onPressed: _opening ? null : () => _open(privacyPolicyUrl),
          icon: const Icon(Icons.open_in_new),
          label: const Text('Privacy policy'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('openTermsOfUse'),
          onPressed: _opening ? null : () => _open(termsOfUseUrl),
          icon: const Icon(Icons.open_in_new),
          label: const Text('Terms of use'),
        ),
      ],
    ),
  );
}
