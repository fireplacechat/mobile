import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/widgets/status.dart';
import 'package:fireplace/src/view/safety/verify_screen.dart';

class NewDeviceBanner extends ConsumerStatefulWidget {
  const NewDeviceBanner({super.key, required this.peerUid, required this.name});
  final String peerUid;
  final String name;
  @override
  ConsumerState<NewDeviceBanner> createState() => _NewDeviceBannerState();
}

class _NewDeviceBannerState extends ConsumerState<NewDeviceBanner> {
  bool _dismissed = false;
  @override
  Widget build(BuildContext context) {
    final fresh =
        ref.watch(newPeerDevicesProvider(widget.peerUid)).value ?? const [];
    if (fresh.isEmpty || _dismissed) return SizedBox.shrink();
    return UiNotice(
      key: const Key('newDeviceBanner'),
      warning: true,
      text:
          '${widget.name} added a new device. If this is unexpected, verify their security code.',
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  VerifyScreen(peerUid: widget.peerUid, peerName: widget.name),
            ),
          ),
          child: const Text('Verify'),
        ),
        TextButton(
          onPressed: () => setState(() => _dismissed = true),
          child: const Text('Dismiss'),
        ),
      ],
    );
  }
}
