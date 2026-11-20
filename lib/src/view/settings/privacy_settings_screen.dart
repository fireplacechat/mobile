import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/passphrase_lock_providers.dart';
import 'package:fireplace/src/view/lock/passphrase_lock_screen.dart';
import 'package:fireplace/src/view/safety/blocked_users_screen.dart';
import 'package:fireplace/src/view/settings/security_code_screen.dart';
import 'package:fireplace/src/view/settings/settings_actions.dart';
import 'package:fireplace/src/view/settings/settings_category.dart';
import 'package:fireplace/src/widgets/settings/settings_page.dart';
import 'package:fireplace/src/widgets/settings_section.dart';

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
  Widget build(BuildContext context) => SettingsPage(
    key: SettingsCategory.privacy.pageKey,
    title: SettingsCategory.privacy.title,
    children: [
      ...errorRows,
      UiSettingsSection(
        title: 'Privacy and security',
        children: [
          // Codes are behind a row that says what they are for, not shown
          // here as hex (issue 202).
          ListTile(
            key: const Key('securityCode'),
            leading: const Icon(Icons.fingerprint),
            title: const Text('Security code'),
            trailing: const Icon(Icons.chevron_right),
            onTap: busy ? null : () => open(const SecurityCodeScreen()),
          ),
          if (ref.watch(passphraseLockServiceProvider) != null)
            ListTile(
              key: const Key('passphraseLock'),
              leading: const Icon(Icons.lock_outline),
              title: const Text('Passphrase lock'),
              subtitle: Text(
                ref.watch(passphraseLockProvider).value?.on == true
                    ? 'On'
                    : 'Off',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: busy ? null : () => open(const PassphraseLockScreen()),
            ),
          ListTile(
            key: const Key('blockedPeople'),
            leading: const Icon(Icons.block),
            title: const Text('Blocked people'),
            trailing: const Icon(Icons.chevron_right),
            onTap: busy ? null : () => open(const BlockedUsersScreen()),
          ),
        ],
      ),
    ],
  );
}
