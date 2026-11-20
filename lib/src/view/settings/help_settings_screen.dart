import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/model/notifications/preview_diagnostics.dart';
import 'package:fireplace/src/view/settings/legal_links.dart';
import 'package:fireplace/src/view/settings/preview_diagnostics_screen.dart';
import 'package:fireplace/src/view/settings/settings_actions.dart';
import 'package:fireplace/src/view/settings/settings_category.dart';
import 'package:fireplace/src/widgets/settings/settings_group.dart';
import 'package:fireplace/src/widgets/settings/settings_page.dart';
import 'package:fireplace/src/widgets/settings/settings_tile.dart';

/// Settings → Help and about: the privacy policy, terms of use and the
/// open-source licences.
///
/// The app version is not shown: reading it needs a plugin the app does not
/// have, and a copy in the code could fall out of step with the release.
class HelpSettingsScreen extends ConsumerStatefulWidget {
  const HelpSettingsScreen({super.key});

  @override
  ConsumerState<HelpSettingsScreen> createState() => _HelpSettingsScreenState();
}

class _HelpSettingsScreenState extends ConsumerState<HelpSettingsScreen>
    with SettingsActions {
  @override
  Widget build(BuildContext context) {
    const category = SettingsCategory.help;
    return SettingsPage(
      key: category.pageKey,
      title: category.title,
      children: [
        ...errorRows,
        SettingsGroup(
          children: [
            SettingsTile(
              key: const Key('openPrivacyPolicy'),
              leading: const SettingsCategoryIcon(
                category,
                Icons.policy_rounded,
              ),
              title: 'Privacy policy',
              onLongPress: previewDiagnosticsEnabled
                  ? () => open(const PreviewDiagnosticsScreen())
                  : null,
              onTap: busy ? null : () => openLegal(privacyPolicyUrl),
            ),
            SettingsTile(
              key: const Key('openTermsOfUse'),
              leading: const SettingsCategoryIcon(
                category,
                Icons.description_rounded,
              ),
              title: 'Terms of use',
              onTap: busy ? null : () => openLegal(termsOfUseUrl),
            ),
            // Flutter's own licence page, until ours is designed.
            SettingsTile(
              key: const Key('openLicences'),
              leading: const SettingsCategoryIcon(category, Icons.code_rounded),
              title: 'Open-source licences',
              onTap: busy
                  ? null
                  : () => showLicensePage(
                      context: context,
                      applicationName: 'Fireplace',
                    ),
            ),
          ],
        ),
      ],
    );
  }
}
