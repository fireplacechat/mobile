import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/styles/action_icons.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/view/account/account_deletion_screens.dart';
import 'package:fireplace/src/view/account/change_password_dialog.dart';
import 'package:fireplace/src/view/settings/settings_actions.dart';
import 'package:fireplace/src/view/settings/settings_category.dart';
import 'package:fireplace/src/widgets/settings_section.dart';

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
    final danger = FireplaceUiTokens.of(context).danger;
    return SettingsSessionPage(
      key: SettingsCategory.account.pageKey,
      title: SettingsCategory.account.title,
      builder: (s) => [
        ...errorRows,
        UiSettingsSection(
          title: 'Account',
          children: [
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text('@${s.username}'),
              subtitle: const Text('Your username'),
            ),
            ListTile(
              key: const Key('changePassword'),
              leading: const Icon(Icons.password),
              title: const Text('Change password'),
              onTap: busy
                  ? null
                  : () => run(() => showChangePasswordDialog(context, ref)),
            ),
          ],
        ),
        UiSettingsSection(
          title: 'Account actions',
          children: [
            ListTile(
              key: const Key('signOut'),
              leading: Icon(Icons.logout, color: danger),
              title: const Text('Sign out'),
              onTap: busy
                  ? null
                  : () => run(() async {
                      await ref.read(authServiceProvider).signOut();
                      if (context.mounted) {
                        Navigator.of(context).popUntil((r) => r.isFirst);
                      }
                    }),
            ),
            ListTile(
              key: const Key('deleteAccountTile'),
              leading: Icon(ActionIcons.delete, color: danger),
              title: Text('Delete account', style: TextStyle(color: danger)),
              onTap: busy ? null : () => open(const DeleteAccountScreen()),
            ),
          ],
        ),
      ],
    );
  }
}
