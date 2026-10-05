import 'package:flutter/material.dart';

import 'presentation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../services/key_service.dart';
import 'design_tokens.dart';

class DevicesScreen extends ConsumerStatefulWidget {
  const DevicesScreen({super.key});
  @override
  ConsumerState<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends ConsumerState<DevicesScreen> {
  late Future<List<DeviceInfo>> _devices = _load();

  String? _revoking, _error;

  Future<List<DeviceInfo>> _load() async {
    final s = ref.read(appSessionProvider).value;
    if (s == null) throw StateError('Account is not ready');
    return s.keys.listOwnDevices(s.uid, s.device.keys.deviceId);
  }

  Future<void> _revoke(DeviceInfo d) async {
    if (_revoking != null) return;
    setState(() {
      _revoking = d.deviceId;
      _error = null;
    });
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => UiDialog(
          title: const Text('Remove this device?'),
          content: const SingleChildScrollView(
            child: Text(
              'It will stop receiving new messages and will have to be set up again. Messages it already received stay on it.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              key: const Key('confirmRevoke'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                'Remove',
                style: TextStyle(color: FireplaceUiTokens.of(context).danger),
              ),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      final s = ref.read(appSessionProvider).value;
      if (s == null) throw StateError('Account is not ready');
      await s.keys.revokeDevice(
        s.uid,
        d.deviceId,
        thisDeviceId: s.device.keys.deviceId,
      );
      if (mounted) setState(() => _devices = _load());
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not remove this device. Try again.');
      }
    } finally {
      if (mounted) setState(() => _revoking = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: UiAppBar(context: context, title: Text('Your devices')),
    body: FutureBuilder<List<DeviceInfo>>(
      future: _devices,
      builder: (context, snap) {
        if (snap.hasError) {
          return UiEmptyState(
            title: 'Could not load devices',
            message: 'Try again to view your devices.',
            action: TextButton(
              onPressed: () => setState(() => _devices = _load()),
              child: Text('Try again'),
            ),
          );
        }
        if (!snap.hasData) {
          return Center(child: CircularProgressIndicator());
        }
        return UiPageScroll(
          children: [
            Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                "Messages are encrypted separately for each device. If you "
                "don't recognise one, remove it.",
              ),
            ),
            if (_error != null)
              UiActionError(
                key: const Key('deviceActionError'),
                message: _error!,
              ),
            if (_revoking != null)
              const LinearProgressIndicator(semanticsLabel: 'Removing device'),
            for (final d in snap.data!)
              ListTile(
                leading: Icon(
                  d.isThisDevice ? Icons.phone_android : Icons.devices_other,
                  color: d.revoked
                      ? FireplaceUiTokens.of(context).secondaryText
                      : FireplaceUiTokens.of(context).accent,
                ),
                title: Text(
                  d.deviceId,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 14,
                    decoration: d.revoked ? TextDecoration.lineThrough : null,
                  ),
                ),
                subtitle: Text(
                  d.isThisDevice
                      ? 'This device'
                      : d.revoked
                      ? 'Removed'
                      : 'Added ${d.createdAt?.toLocal().toString().split('.').first ?? ''}',
                ),
                trailing: (d.isThisDevice || d.revoked)
                    ? null
                    : IconButton(
                        key: Key('revoke_${d.deviceId}'),
                        tooltip: 'Remove device',
                        icon: Icon(
                          Icons.delete_outline,
                          color: FireplaceUiTokens.of(context).danger,
                        ),
                        onPressed: _revoking == null ? () => _revoke(d) : null,
                      ),
              ),
          ],
        );
      },
    ),
  );
}
