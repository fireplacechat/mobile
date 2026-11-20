import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/passphrase_lock_providers.dart';
import 'package:fireplace/src/view/lock/passphrase_lock_screen.dart';
import 'package:fireplace/src/view/safety/blocked_users_screen.dart';
import 'package:fireplace/src/view/settings/security_code_screen.dart';
import 'package:fireplace/src/view/settings/settings_actions.dart';
import 'package:fireplace/src/view/settings/settings_category.dart';
import 'package:fireplace/src/widgets/settings/settings_group.dart';
import 'package:fireplace/src/widgets/settings/settings_page.dart';
import 'package:fireplace/src/widgets/settings/settings_tile.dart';

/// Settings → Privacy and security: your security code, the passphrase
/// lock and the people you blocked.
class PrivacySettingsScreen extends ConsumerStatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  ConsumerState<PrivacySettingsScreen> createState() =>
      _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends ConsumerState<PrivacySettingsScreen>
    with SettingsActions {
  @override
  Widget build(BuildContext context) {
    const category = SettingsCategory.privacy;
    return SettingsPage(
      key: category.pageKey,
      title: category.title,
      children: [
        ...errorRows,
        SettingsGroup(
          children: [
            // Codes are behind a row that says what they are for, not shown
            // here as hex (issue 202).
            SettingsTile(
              key: const Key('securityCode'),
              leading: const SettingsCategoryIcon(
                category,
                Icons.fingerprint_rounded,
              ),
              title: 'Security code',
              onTap: busy ? null : () => open(const SecurityCodeScreen()),
            ),
            if (ref.watch(passphraseLockServiceProvider) != null)
              SettingsTile(
                key: const Key('passphraseLock'),
                leading: const SettingsCategoryIcon(
                  category,
                  Icons.lock_rounded,
                ),
                title: 'Passphrase lock',
                value: ref.watch(passphraseLockProvider).value?.on == true
                    ? 'On'
                    : 'Off',
                onTap: busy ? null : () => open(const PassphraseLockScreen()),
              ),
            SettingsTile(
              key: const Key('blockedPeople'),
              leading: const SettingsCategoryIcon(
                category,
                Icons.block_rounded,
              ),
              title: 'Blocked people',
              onTap: busy ? null : () => open(const BlockedUsersScreen()),
            ),
          ],
        ),
      ],
    );
  }
}
