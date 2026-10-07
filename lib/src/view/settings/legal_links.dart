import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fireplace/src/widgets/app_bar.dart';
import 'package:fireplace/src/widgets/page.dart';
import 'package:fireplace/src/widgets/status.dart';
import 'package:fireplace/src/styles/brand/lockup.dart';

/// Where the current privacy policy and terms live. The pages are generated from `site/pages/`.
const privacyPolicyUrl = 'https://fireplacechat.com/privacy/';
const termsOfUseUrl = 'https://fireplacechat.com/terms/';

/// Selectable legal addresses with explicit clipboard copying. No browser or network
/// integration is introduced here; store-policy acceptance remains a launch gate.
class LegalLinksScreen extends StatelessWidget {
  const LegalLinksScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: UiAppBar(context: context, title: const Text('Privacy and terms')),
    body: UiPageScroll(
      children: [
        FireplaceBrandText(
          'These pages are on the Fireplace website. Copy a link and open it in your browser.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        const _LegalLink(
          id: 'privacy',
          title: 'Privacy policy',
          blurb: 'What Fireplace handles, why, and for how long.',
          url: privacyPolicyUrl,
        ),
        const SizedBox(height: 12),
        const _LegalLink(
          id: 'terms',
          title: 'Terms of use',
          blurb: 'The rules for using Fireplace.',
          url: termsOfUseUrl,
        ),
      ],
    ),
  );
}

class _LegalLink extends StatefulWidget {
  const _LegalLink({
    required this.id,
    required this.title,
    required this.blurb,
    required this.url,
  });
  final String id, title, blurb, url;

  @override
  State<_LegalLink> createState() => _LegalLinkState();
}

class _LegalLinkState extends State<_LegalLink> {
  bool _copying = false;
  String? _error;
  Future<void> _copy() async {
    if (_copying) return;
    setState(() {
      _copying = true;
      _error = null;
    });
    try {
      await Clipboard.setData(ClipboardData(text: widget.url));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Link copied')));
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not copy the link. Try again, or select the address above.',
        );
      }
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          title: Text(widget.title),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FireplaceBrandText(widget.blurb),
                const SizedBox(height: 4),
                SelectableText(widget.url),
              ],
            ),
          ),
          trailing: IconButton(
            key: Key('copyLink-${widget.id}'),
            tooltip: 'Copy ${widget.title.toLowerCase()} link',
            icon: Icon(_copying ? Icons.hourglass_top : Icons.copy_outlined),
            onPressed: _copying ? null : _copy,
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: UiActionError(message: _error!),
          ),
      ],
    ),
  );
}
