import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/model/notifications/preview_diagnostics.dart';
import 'package:fireplace/src/view/settings/legal_links.dart';
import 'package:fireplace/src/view/settings/preview_diagnostics_screen.dart';
import 'package:fireplace/src/view/settings/settings_actions.dart';
import 'package:fireplace/src/view/settings/settings_category.dart';
import 'package:fireplace/src/widgets/settings/settings_page.dart';
import 'package:fireplace/src/widgets/settings_section.dart';

/// Settings → Help and about: the privacy policy and terms of use.
class HelpSettingsScreen extends ConsumerStatefulWidget {
  const HelpSettingsScreen({super.key});

  @override
  ConsumerState<HelpSettingsScreen> createState() => _HelpSettingsScreenState();
}

class _HelpSettingsScreenState extends ConsumerState<HelpSettingsScreen>
    with SettingsActions {
  @override
  Widget build(BuildContext context) => SettingsPage(
    key: SettingsCategory.help.pageKey,
    title: SettingsCategory.help.title,
    children: [
      ...errorRows,
      UiSettingsSection(
        title: 'About',
        children: [
          ListTile(
            key: const Key('openPrivacyPolicy'),
            leading: const Icon(Icons.policy_outlined),
            title: const Text('Privacy policy'),
            onLongPress: previewDiagnosticsEnabled
                ? () => open(const PreviewDiagnosticsScreen())
                : null,
            trailing: const Icon(Icons.chevron_right),
            onTap: busy ? null : () => openLegal(privacyPolicyUrl),
          ),
          ListTile(
            key: const Key('openTermsOfUse'),
            leading: const Icon(Icons.description_outlined),
            title: const Text('Terms of use'),
            trailing: const Icon(Icons.chevron_right),
            onTap: busy ? null : () => openLegal(termsOfUseUrl),
          ),
        ],
      ),
    ],
  );
}
