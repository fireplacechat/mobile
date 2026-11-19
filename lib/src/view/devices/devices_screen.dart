import 'package:flutter/material.dart';

import 'package:fireplace/src/widgets/app_bar.dart';
import 'package:fireplace/src/widgets/page.dart';
import 'package:fireplace/src/widgets/status.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/keys/key_service.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/view/safety/safety_action_sheet.dart';
import 'package:fireplace/src/widgets/clock_time.dart';
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

  /// When the device was added and its id, for whoever needs it.
  Future<void> _showDetails(DeviceInfo d, String name) {
    final l = MaterialLocalizations.of(context);
    final added = d.createdAt;
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: FireplaceUiTokens.of(context).panel,
      builder: (ctx) => SafeArea(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            key: const Key('deviceDetails'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: Theme.of(ctx).textTheme.titleLarge),
              if (added != null) ...[
                const SizedBox(height: 16),
                Text('Added', style: Theme.of(ctx).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  '${l.formatFullDate(added.toLocal())}, ${clockTime(added, l)}',
                ),
              ],
              const SizedBox(height: 16),
              Text('Device ID', style: Theme.of(ctx).textTheme.titleSmall),
              const SizedBox(height: 4),
              SelectableText(
                d.deviceId,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
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
        final names = deviceNames(
          snap.data!,
          MaterialLocalizations.of(context),
          now: DateTime.now(),
        );
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
                key: Key('device_${d.deviceId}'),
                leading: Icon(
                  d.isThisDevice ? Icons.phone_android : Icons.devices_other,
                  color: d.revoked
                      ? FireplaceUiTokens.of(context).secondaryText
                      : FireplaceUiTokens.of(context).accent,
                ),
                title: Text(
                  names[d.deviceId]!,
                  style: TextStyle(
                    decoration: d.revoked ? TextDecoration.lineThrough : null,
                  ),
                ),
                subtitle: d.revoked ? const Text('Removed') : null,
                // The id stays available, one tap away.
                onTap: () => _showDetails(d, names[d.deviceId]!),
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

/// Each device under a name a person can match to a phone (issue 202),
/// without storing anything new: "This phone", or "Phone added Nov 14" from
/// when it was added. Two added the same day also get the time.
Map<String, String> deviceNames(
  List<DeviceInfo> devices,
  MaterialLocalizations l, {
  required DateTime now,
}) {
  String day(DateTime at) {
    final local = at.toLocal();
    return local.year == now.toLocal().year
        ? l.formatShortMonthDay(local)
        : l.formatShortDate(local);
  }

  String base(DeviceInfo d) => d.isThisDevice
      ? 'This phone'
      : d.createdAt == null
      ? 'Another phone'
      : 'Phone added ${day(d.createdAt!)}';
  final counts = <String, int>{};
  for (final d in devices) {
    counts.update(base(d), (n) => n + 1, ifAbsent: () => 1);
  }
  return {
    for (final d in devices)
      d.deviceId: !d.isThisDevice && d.createdAt != null && counts[base(d)]! > 1
          ? '${base(d)}, ${clockTime(d.createdAt!, l)}'
          : base(d),
  };
}
