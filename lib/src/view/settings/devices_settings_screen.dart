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
import 'package:fireplace/src/widgets/settings/settings_group.dart';
import 'package:fireplace/src/widgets/settings/settings_tile.dart';

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
  Widget build(BuildContext context) {
    const category = SettingsCategory.devices;
    return SettingsSessionPage(
      key: category.pageKey,
      title: category.title,
      builder: (s) => [
        ...errorRows,
        SettingsGroup(
          children: [
            SettingsTile(
              key: const Key('devices'),
              leading: const SettingsCategoryIcon(
                category,
                Icons.devices_outlined,
              ),
              title: 'Your devices',
              onTap: busy ? null : () => open(const DevicesScreen()),
            ),
            SettingsTile(
              key: const Key('linkDevice'),
              leading: const SettingsCategoryIcon(
                category,
                Icons.add_to_home_screen_outlined,
              ),
              title: 'Link a new device',
              onTap: busy ? null : () => open(const LinkNewDeviceScreen()),
            ),
          ],
        ),
        SettingsGroup(
          children: [
            SettingsTile(
              key: const Key('recoveryKey'),
              leading: const SettingsCategoryIcon(category, Icons.key_outlined),
              title: 'Recovery key',
              onTap: busy ? null : () => open(const RecoveryKeyScreen()),
            ),
            // Offered only where the server keeps a new phone waiting.
            if (ref.watch(lostPhoneWaitProvider(s.uid)).value case final wait?)
              LostPhoneWaitTile(
                wait: wait,
                enabled: !busy,
                onChanged: (wait) => _setWait(s, wait),
                leading: const SettingsCategoryIcon(
                  category,
                  Icons.hourglass_empty_rounded,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
