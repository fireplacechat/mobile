import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:fireplace/src/model/keys/recovery_service.dart';
import 'package:fireplace/src/widgets/app_bar.dart';
import 'package:fireplace/src/widgets/page.dart';
import 'package:fireplace/src/widgets/status.dart';

/// New device side of linking: show the QR code and wait. The answer of the
/// device that scanned it is opened and installed without another step.
class LinkWaitScreen extends ConsumerStatefulWidget {
  const LinkWaitScreen({super.key, required this.uid});
  final String uid;
  @override
  ConsumerState<LinkWaitScreen> createState() => _LinkWaitScreenState();
}

class _LinkWaitScreenState extends ConsumerState<LinkWaitScreen> {
  LinkRequest? _req;
  String? _error;
  bool _starting = false, _linking = false, _completed = false;
  int _attempt = 0;
  late final RecoveryService _service;

  @override
  void initState() {
    super.initState();
    _service = ref.read(recoveryServiceProvider);
    _start();
  }

  Future<void> _start() async {
    if (_starting || _linking) return;
    final attempt = ++_attempt;
    final old = _req;
    setState(() {
      _starting = true;
      _req = null;
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
      if (!mounted || attempt != _attempt) return;
      setState(() => _linking = true);
      await _service.completeLink(req, sealed);
      _completed = true;
      if (mounted) ref.invalidate(appSessionProvider);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on RecoveryException catch (e) {
      if (mounted && attempt == _attempt) setState(() => _error = e.message);
    } catch (_) {
      if (mounted && attempt == _attempt) {
        setState(() => _error = 'Could not link this device. Try again.');
      }
    } finally {
      if (mounted && attempt == _attempt) {
        setState(() {
          _starting = false;
          _linking = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _attempt++;
    final req = _req;
    if (req != null && !_completed) _service.cancelLink(req).catchError((_) {});
    super.dispose();
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
          else if (_linking) ...[
            Center(child: CircularProgressIndicator()),
            SizedBox(height: 12),
            Center(child: Text('Linking…')),
          ] else if (req != null) ...[
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
          ],
          if (_error != null) UiActionError(message: _error!),
          if (_error != null)
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
