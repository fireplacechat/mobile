import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/keys/recovery_service.dart';
import 'package:fireplace/src/widgets/qr_scan_page.dart';
import 'package:fireplace/src/styles/brand/logo.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/widgets/app_bar.dart';
import 'package:fireplace/src/widgets/page.dart';
import 'package:fireplace/src/widgets/status.dart';

/// Existing-device side of linking: scan the new device's QR code. That is
/// the whole approval; the new device finishes on its own.
class LinkNewDeviceScreen extends ConsumerStatefulWidget {
  const LinkNewDeviceScreen({super.key, this.scanCode});
  final Future<String?> Function(BuildContext)? scanCode;
  @override
  ConsumerState<LinkNewDeviceScreen> createState() =>
      _LinkNewDeviceScreenState();
}

class _LinkNewDeviceScreenState extends ConsumerState<LinkNewDeviceScreen> {
  final _scroll = ScrollController();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  bool _approved = false;
  String? _error;
  bool _busy = false;

  Future<void> _scan() async {
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
      final raw = widget.scanCode != null
          ? await widget.scanCode!(context)
          : await Navigator.of(context).push<String>(
              MaterialPageRoute(
                builder: (_) => const QrScanPage(title: 'Scan the new device'),
              ),
            );
      if (raw == null || !mounted) return;
      await ref
          .read(recoveryServiceProvider)
          .approveLink(s.uid, s.device.identity, raw);
      if (mounted) {
        setState(() => _approved = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
        });
      }
    } on RecoveryException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not approve the link. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: UiAppBar(context: context),
    body: UiPageScroll(
      controller: _scroll,
      maxWidth: 520,
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
      children: [
        Center(
          child: Icon(
            _approved
                ? Icons.check_circle_outline_rounded
                : Icons.add_to_home_screen_rounded,
            size: 56,
            color: fireplaceOrange,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          _approved ? 'Device linked' : 'Link a new device',
          key: _approved ? const Key('linkApproved') : null,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 12),
        Text(
          _approved
              ? 'Not you? Remove it in Settings, under Your devices.'
              : 'Keep your identity. Add a device you trust.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 24),
        if (!_approved) ...[
          const _LinkStep(
            number: '1',
            title: 'Sign in on the new device',
            text: 'Use your existing username and password.',
          ),
          const _LinkStep(
            number: '2',
            title: 'Show its QR code',
            text: 'Choose “Link with your other device” on the new device.',
          ),
          const _LinkStep(
            number: '3',
            title: 'Scan it here',
            text: 'The new device finishes on its own.',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('scanLink'),
            onPressed: _busy ? null : _scan,
            icon: const Icon(Icons.qr_code_scanner),
            label: Text(_busy ? 'Linking…' : 'Scan the new device'),
          ),
          const SizedBox(height: 16),
          const Text(
            'Only link a device you hold in your hands. Past messages stay on the devices that received them.',
            textAlign: TextAlign.center,
          ),
        ] else
          FilledButton(
            key: const Key('linkDone'),
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Done'),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: UiActionError(message: _error!),
          ),
      ],
    ),
  );
}

class _LinkStep extends StatelessWidget {
  const _LinkStep({
    required this.number,
    required this.title,
    required this.text,
  });
  final String number, title, text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: FireplaceUiTokens.of(context).selectedRow,
              child: Text(
                number,
                style: TextStyle(
                  color: FireplaceUiTokens.of(context).accentText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              text,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    ),
  );
}
