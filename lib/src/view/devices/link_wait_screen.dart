import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:fireplace/src/crypto/link.dart';
import 'package:fireplace/src/model/keys/recovery_service.dart';
import 'package:fireplace/src/widgets/app_bar.dart';
import 'package:fireplace/src/widgets/page.dart';
import 'package:fireplace/src/widgets/status.dart';

/// New device side of linking: show the QR, wait, then confirm the 6-digit code.
class LinkWaitScreen extends ConsumerStatefulWidget {
  const LinkWaitScreen({super.key, required this.uid});
  final String uid;
  @override
  ConsumerState<LinkWaitScreen> createState() => _LinkWaitScreenState();
}

class _LinkWaitScreenState extends ConsumerState<LinkWaitScreen> {
  LinkRequest? _req;
  SealedIdentity? _sealed;
  final _code = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _starting = false, _completed = false;
  int _attempt = 0;
  late final RecoveryService _service;

  @override
  void initState() {
    super.initState();
    _service = ref.read(recoveryServiceProvider);
    _start();
  }

  Future<void> _start() async {
    if (_starting || _busy) return;
    final attempt = ++_attempt;
    final old = _req;
    setState(() {
      _starting = true;
      _req = null;
      _sealed = null;
      _error = null;
    });
    try {
      if (old != null) await _service.cancelLink(old);
      if (!mounted) return;
      final req = await _service.startLink(widget.uid);
      if (!mounted || attempt != _attempt) {
        await _service.cancelLink(req);
        return;
      }
      setState(() {
        _req = req;
        _starting = false;
      });
      final sealed = await _service.awaitResponse(req);
      if (mounted && attempt == _attempt) setState(() => _sealed = sealed);
    } on RecoveryException catch (e) {
      if (mounted && attempt == _attempt) setState(() => _error = e.message);
    } catch (_) {
      if (mounted && attempt == _attempt) {
        setState(() => _error = 'Could not link this device. Try again.');
      }
    } finally {
      if (mounted && attempt == _attempt) setState(() => _starting = false);
    }
  }

  @override
  void dispose() {
    _attempt++;
    _code.dispose();
    final req = _req;
    if (req != null && !_completed) _service.cancelLink(req).catchError((_) {});
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_busy || _req == null || _sealed == null) return;
    final code = _code.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(
        () => _error = 'Enter the 6-digit code shown on your other device.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.completeLink(_req!, _sealed!, code);
      _completed = true;
      if (mounted) ref.invalidate(appSessionProvider);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on RecoveryException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = 'Could not finish linking this device. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final req = _req;
    return Scaffold(
      appBar: UiAppBar(context: context, title: Text('Link this device')),
      body: UiPageScroll(
        padding: EdgeInsets.all(20),
        children: [
          if (req == null && _error == null)
            Center(child: CircularProgressIndicator())
          else if (_sealed == null && req != null) ...[
            Text(
              'On your other device open Settings → Link a new device and scan '
              'this code.',
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16),
            Center(
              child: Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: QrImageView(data: req.qrPayload, size: 220),
              ),
            ),
            SizedBox(height: 12),
            if (_error == null) Center(child: Text('Waiting for approval…')),
          ] else if (_sealed != null) ...[
            Text(
              'Your other device is showing a 6-digit code. Type it here to '
              'finish. This makes sure nobody swapped your keys on the way.',
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16),
            TextField(
              key: Key('linkCode'),
              controller: _code,
              enabled: !_busy,
              onSubmitted: (_) => _confirm(),
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                letterSpacing: 2,
                fontFamily: 'monospace',
              ),
            ),
            FilledButton(
              key: Key('linkConfirm'),
              onPressed: _busy ? null : _confirm,
              child: Text('Confirm'),
            ),
          ],
          if (_error != null) UiActionError(message: _error!),
          if (_error != null && _sealed == null)
            TextButton(
              key: const Key('retryLink'),
              onPressed: _starting ? null : _start,
              child: const Text('Try again'),
            ),
        ],
      ),
    );
  }
}
