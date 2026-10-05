import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/widgets/qr_scan_page.dart';

import 'package:qr_flutter/qr_flutter.dart';

import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/crypto/fingerprint.dart';
import 'package:fireplace/src/model/keys/verify_payload.dart';
import 'package:fireplace/src/styles/theme.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/ui/presentation.dart';
import 'package:fireplace/src/styles/brand/lockup.dart';

class _Info {
  _Info(this.number, this.peerIdentity);
  final String number;
  final List<int> peerIdentity;
}

/// Compare a 60-digit safety number (or scan a QR) to confirm you are talking
/// to the right person and nobody is intercepting.
class VerifyScreen extends ConsumerStatefulWidget {
  const VerifyScreen({
    super.key,
    required this.peerUid,
    required this.peerName,
    this.scanCode,
  });
  final Future<String?> Function(BuildContext)? scanCode;
  final String peerUid;
  final String peerName;
  @override
  ConsumerState<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends ConsumerState<VerifyScreen> {
  late Future<_Info?> _info = _load();
  bool _busy = false;
  String? _error;

  Future<_Info?> _load() async {
    final s = ref.read(appSessionProvider).value;
    if (s == null) return null;
    var peer = await s.keys.pinnedIdentity(widget.peerUid);
    if (peer == null) {
      await s.keys.fetchDevices(widget.peerUid); // pins on first sight
      peer = await s.keys.pinnedIdentity(widget.peerUid);
    }
    if (peer == null) return null;
    return _Info(await safetyNumber(s.device.identity.publicBytes, peer), peer);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not finish verification. Your previous choice is kept. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setVerified(_Info info, bool v) =>
      _run(() => _writeVerified(info, v));
  Future<void> _writeVerified(_Info info, bool v) async {
    final keys = ref.read(appSessionProvider).value?.keys;
    if (keys == null) throw StateError('Account is unavailable');
    if (v) {
      await keys.markVerified(widget.peerUid, info.peerIdentity);
    } else {
      await keys.clearVerified(widget.peerUid);
    }
    if (mounted) ref.invalidate(peerVerifiedProvider(widget.peerUid));
  }

  Future<void> _scan(_Info info) => _run(() async {
    final raw = widget.scanCode != null
        ? await widget.scanCode!(context)
        : await Navigator.of(context).push<String>(
            MaterialPageRoute(
              builder: (_) => const QrScanPage(title: 'Scan their code'),
            ),
          );
    if (raw == null || !mounted) return;
    final p = VerifyPayload.parse(raw);
    final ok = p != null && p.matches(info.number);
    if (ok) await _writeVerified(info, true);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => UiDialog(
        icon: Icon(
          ok ? Icons.verified_user : Icons.gpp_bad,
          color: ok ? Colors.green : FireplaceUiTokens.of(context).danger,
          size: 40,
        ),
        title: Text(ok ? 'Verified' : "Codes don't match"),
        content: FireplaceBrandText(
          ok
              ? 'Your security code with ${widget.peerName} matches. Messages '
                    'use the identities represented by this code.'
              : p == null
              ? "That isn't a Fireplace verification code."
              : 'The code does not match. Someone may be intercepting your '
                    'messages, or one of you reinstalled the app. Do not '
                    'share anything sensitive until you resolve this.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('OK')),
        ],
      ),
    );
  });

  @override
  Widget build(BuildContext context) {
    final verified =
        ref.watch(peerVerifiedProvider(widget.peerUid)).value ?? false;
    return Scaffold(
      appBar: UiAppBar(
        context: context,
        title: Text('Verify ${widget.peerName}'),
      ),
      body: FutureBuilder<_Info?>(
        future: _info,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return UiEmptyState(
              title: 'Could not load security code',
              message: 'Try again to load the code for this contact.',
              action: TextButton(
                onPressed: () => setState(() => _info = _load()),
                child: const Text('Try again'),
              ),
            );
          }
          final info = snap.data;
          if (info == null) {
            return Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "This contact hasn't published encryption keys yet.",
                ),
              ),
            );
          }
          final groups = info.number.split(' ');
          return UiPageScroll(
            padding: EdgeInsets.all(20),
            children: [
              Center(
                child: UiStatus(
                  label: verified ? 'Verified' : 'Not verified yet',
                  icon: verified ? Icons.verified_user : Icons.shield_outlined,
                ),
              ),
              SizedBox(height: 16),
              Center(
                child: Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: QrImageView(
                    data: VerifyPayload.fromSafetyNumber(info.number).encode(),
                    size: 200,
                    eyeStyle: QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: FP.hearth,
                    ),
                    dataModuleStyle: QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: FP.hearth,
                    ),
                  ),
                ),
              ),
              SizedBox(height: 16),
              Center(
                child: Wrap(
                  spacing: 18,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: [
                    for (var i = 0; i < groups.length; i++)
                      Text(
                        groups[i],
                        key: Key('safetyGroup_$i'),
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(height: 16),
              Text(
                'Compare this number with ${widget.peerName}, in person or over '
                'a call you trust. Matching numbers confirm that both devices use the same encryption identities. You can also scan their QR code.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (_error != null)
                UiActionError(
                  key: const Key('verificationError'),
                  message: _error!,
                ),
              if (_busy)
                const LinearProgressIndicator(
                  semanticsLabel: 'Updating verification',
                ),
              SizedBox(height: 20),
              FilledButton.icon(
                key: Key('scan'),
                onPressed: _busy ? null : () => _scan(info),
                icon: Icon(Icons.qr_code_scanner),
                label: Text('Scan their code'),
              ),
              SizedBox(height: 8),
              OutlinedButton.icon(
                key: Key('toggleVerified'),
                onPressed: _busy ? null : () => _setVerified(info, !verified),
                icon: Icon(verified ? Icons.remove_done : Icons.done_all),
                label: Text(
                  verified ? 'Mark as not verified' : 'The numbers match',
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
