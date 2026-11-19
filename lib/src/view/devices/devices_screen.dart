import 'package:flutter/material.dart';

import 'package:fireplace/src/widgets/app_bar.dart';
import 'package:fireplace/src/widgets/page.dart';
import 'package:fireplace/src/widgets/status.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/keys/key_service.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/view/safety/safety_action_sheet.dart';
import 'package:fireplace/src/styles/action_icons.dart';

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
      final ok = await showSafetyActionSheet<bool>(
        context: context,
        title: 'Remove this device?',
        message: 'It stops receiving new messages.',
        actions: const [
          SafetySheetAction(
            label: 'Remove',
            value: true,
            style: SafetyActionStyle.destructive,
            buttonKey: Key('confirmRevoke'),
          ),
          SafetySheetAction(label: 'Cancel', value: false),
        ],
      );
      if (ok != true || !mounted) return;
      final s = ref.read(appSessionProvider).value;
      if (s == null) throw StateError('Account is not ready');
      await ref
          .read(takeoverServiceProvider)
          .removeDevice(
            s.uid,
            s.device,
            d.deviceId,
            direct: () => s.keys.revokeDevice(
              s.uid,
              d.deviceId,
              thisDeviceId: s.device.keys.deviceId,
            ),
          );
      if (!mounted) return;
      // The device is removed; the next question is a separate one.
      setState(() {
        _devices = _load();
        _revoking = null;
      });
      await _askIfLost();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not remove this device. Try again.');
      }
    } finally {
      if (mounted) setState(() => _revoking = null);
    }
  }

  /// A device in someone else's hands still holds this account's identity
  /// key, so removing it is not enough: the identity is replaced, and with it
  /// everything that key vouched for (decision 0062). Asked once the device
  /// is removed, so each question has one answer to give.
  Future<void> _askIfLost() async {
    final reset = await showSafetyActionSheet<bool>(
      context: context,
      title: 'Was it lost or stolen?',
      message:
          'Reset your security code to lock it out. Your other devices and '
          'groups need setting up again.',
      actions: const [
        SafetySheetAction(
          label: 'Reset security code',
          value: true,
          style: SafetyActionStyle.destructive,
          buttonKey: Key('resetAfterLoss'),
        ),
        SafetySheetAction(
          label: 'No, I have it',
          value: false,
          buttonKey: Key('keepIdentity'),
        ),
      ],
    );
    if (reset != true || !mounted) return;
    try {
      final s = ref.read(appSessionProvider).value;
      if (s == null) throw StateError('Account is not ready');
      final recovery = ref.read(recoveryServiceProvider);
      // While the old identity can still speak: tell the groups.
      await s.groups?.leaveAll();
      // A device replaces the identity at once: it asks the server, which
      // otherwise makes a start wait (decision 0063).
      await ref.read(takeoverServiceProvider).resetNow(s.uid, s.device);
      await recovery.resetIdentity(s.uid);
      // Everything in the session was built on the old identity.
      if (mounted) ref.invalidate(appSessionProvider);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not reset your security code. Try again.',
        );
      }
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
                          ActionIcons.delete,
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
