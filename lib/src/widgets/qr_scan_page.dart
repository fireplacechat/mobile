import 'package:flutter/material.dart';

import 'package:fireplace/src/widgets/app_bar.dart';
import 'package:fireplace/src/widgets/page.dart';

import 'package:mobile_scanner/mobile_scanner.dart';

/// Full-screen QR scanner that pops with the first code it reads.
class QrScanPage extends StatefulWidget {
  const QrScanPage({super.key, this.title = 'Scan code'});
  final String title;
  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  bool _done = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: UiAppBar(context: context, title: Text(widget.title)),
    body: MobileScanner(
      placeholderBuilder: (context) =>
          const Center(child: CircularProgressIndicator()),
      errorBuilder: (context, error) => UiEmptyState(
        title: 'Camera is unavailable',
        message: 'Allow camera access in your device settings, then try again. You can also go back.',
        action: TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('Go back'),
        ),
      ),
      onDetect: (capture) {
        if (_done) return;
        final raw = capture.barcodes.firstOrNull?.rawValue;
        if (raw == null) return;
        _done = true;
        Navigator.of(context).pop(raw);
      },
    ),
  );
}
