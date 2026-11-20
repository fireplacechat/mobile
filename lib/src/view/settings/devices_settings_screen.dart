import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/account/takeover.dart';
import 'package:fireplace/src/view/account/lost_phone_wait_screen.dart';
import 'package:fireplace/src/view/devices/devices_screen.dart';
import 'package:fireplace/src/view/devices/link_new_device_screen.dart';
import 'package:fireplace/src/view/recovery/recovery_key_screen.dart';
import 'package:fireplace/src/view/settings/settings_actions.dart';
import 'package:fireplace/src/view/settings/settings_category.dart';
import 'package:fireplace/src/widgets/settings_section.dart';

/// Settings → Devices and recovery: your devices, the recovery key, how
/// long a new phone waits, and linking a new device.
class DevicesSettingsScreen extends ConsumerStatefulWidget {
  const DevicesSettingsScreen({super.key});

  @override
  ConsumerState<DevicesSettingsScreen> createState() =>
      _DevicesSettingsScreenState();
}

class _DevicesSettingsScreenState extends ConsumerState<DevicesSettingsScreen>
    with SettingsActions {
  Future<void> _setWait(AppSession s, LostPhoneWait wait) => run(() async {
    await ref.read(takeoverServiceProvider).setWait(s.uid, s.device, wait);
    ref.invalidate(lostPhoneWaitProvider(s.uid));
  });

  @override
  Widget build(BuildContext context) => SettingsSessionPage(
    key: SettingsCategory.devices.pageKey,
    title: SettingsCategory.devices.title,
    builder: (s) => [
      ...errorRows,
      UiSettingsSection(
        title: 'Devices and recovery',
        children: [
          ListTile(
            key: const Key('devices'),
            leading: const Icon(Icons.devices),
            title: const Text('Your devices'),
            trailing: const Icon(Icons.chevron_right),
            onTap: busy ? null : () => open(const DevicesScreen()),
          ),
          ListTile(
            key: const Key('recoveryKey'),
            leading: const Icon(Icons.key),
            title: const Text('Recovery key'),
            trailing: const Icon(Icons.chevron_right),
            onTap: busy ? null : () => open(const RecoveryKeyScreen()),
          ),
          // Offered only where the server keeps a new phone waiting.
          if (ref.watch(lostPhoneWaitProvider(s.uid)).value case final wait?)
            LostPhoneWaitTile(
              wait: wait,
              enabled: !busy,
              onChanged: (wait) => _setWait(s, wait),
            ),
          ListTile(
            key: const Key('linkDevice'),
            leading: const Icon(Icons.add_to_home_screen),
            title: const Text('Link a new device'),
            trailing: const Icon(Icons.chevron_right),
            onTap: busy ? null : () => open(const LinkNewDeviceScreen()),
          ),
        ],
      ),
    ],
  );
}
