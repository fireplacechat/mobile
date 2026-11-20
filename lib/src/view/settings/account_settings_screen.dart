import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/styles/action_icons.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/view/account/account_deletion_screens.dart';
import 'package:fireplace/src/view/account/change_password_dialog.dart';
import 'package:fireplace/src/view/settings/settings_actions.dart';
import 'package:fireplace/src/view/settings/settings_category.dart';
import 'package:fireplace/src/widgets/settings/settings_group.dart';
import 'package:fireplace/src/widgets/settings/settings_icon.dart';
import 'package:fireplace/src/widgets/settings/settings_tile.dart';

/// Settings → Account: your username and password; signing out and deleting
/// the account sit apart at the bottom.
class AccountSettingsScreen extends ConsumerStatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  ConsumerState<AccountSettingsScreen> createState() =>
      _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends ConsumerState<AccountSettingsScreen>
    with SettingsActions {
  @override
  Widget build(BuildContext context) {
    const category = SettingsCategory.account;
    final danger = FireplaceUiTokens.of(context).danger;
    return SettingsSessionPage(
      key: category.pageKey,
      title: category.title,
      builder: (s) => [
        ...errorRows,
        SettingsGroup(
          footer: 'People start a chat with you by your username.',
          children: [
            SettingsTile(
              leading: const SettingsCategoryIcon(
                category,
                Icons.alternate_email_rounded,
              ),
              title: 'Your username',
              value: '@${s.username}',
              chevron: false,
            ),
            SettingsTile(
              key: const Key('changePassword'),
              leading: const SettingsCategoryIcon(
                category,
                Icons.password_rounded,
              ),
              title: 'Change password',
              onTap: busy
                  ? null
                  : () => run(() => showChangePasswordDialog(context, ref)),
            ),
          ],
        ),
        SettingsGroup(
          children: [
            SettingsTile(
              key: const Key('signOut'),
              leading: SettingsIcon.bare(Icons.logout_rounded, color: danger),
              title: 'Sign out',
              chevron: false,
              onTap: busy
                  ? null
                  : () => run(() async {
                      await ref.read(authServiceProvider).signOut();
                      if (context.mounted) {
                        Navigator.of(context).popUntil((r) => r.isFirst);
                      }
                    }),
            ),
            SettingsTile(
              key: const Key('deleteAccountTile'),
              leading: SettingsIcon.bare(ActionIcons.delete, color: danger),
              title: 'Delete account',
              titleColor: danger,
              chevron: false,
              onTap: busy ? null : () => open(const DeleteAccountScreen()),
            ),
          ],
        ),
      ],
    );
  }
}
