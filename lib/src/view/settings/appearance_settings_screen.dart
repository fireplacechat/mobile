import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/chat_color_preference.dart';
import 'package:fireplace/src/view/settings/chat_appearance.dart';
import 'package:fireplace/src/view/settings/settings_actions.dart';
import 'package:fireplace/src/view/settings/settings_category.dart';
import 'package:fireplace/src/view/settings/theme_mode_tile.dart';
import 'package:fireplace/src/widgets/settings/settings_page.dart';
import 'package:fireplace/src/widgets/settings_section.dart';

/// Settings → Appearance: the theme on this device and your colour.
class AppearanceSettingsScreen extends ConsumerStatefulWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  ConsumerState<AppearanceSettingsScreen> createState() =>
      _AppearanceSettingsScreenState();
}

class _AppearanceSettingsScreenState
    extends ConsumerState<AppearanceSettingsScreen>
    with SettingsActions {
  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(chatBubbleColorsProvider);
    return SettingsPage(
      key: SettingsCategory.appearance.pageKey,
      title: SettingsCategory.appearance.title,
      children: [
        ...errorRows,
        UiSettingsSection(
          title: 'Appearance',
          children: [
            const ThemeModeTile(),
            ListTile(
              key: const Key('chatColors'),
              leading: const Icon(Icons.palette_outlined),
              title: const Text('Your color'),
              subtitle: Text(colors.outgoing.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: busy ? null : () => open(const ChatAppearanceScreen()),
            ),
          ],
        ),
      ],
    );
  }
}
