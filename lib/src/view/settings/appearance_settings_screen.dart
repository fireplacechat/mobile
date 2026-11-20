import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/chat_color_preference.dart';
import 'package:fireplace/src/view/settings/chat_appearance.dart';
import 'package:fireplace/src/view/settings/settings_actions.dart';
import 'package:fireplace/src/view/settings/settings_category.dart';
import 'package:fireplace/src/view/settings/theme_mode_tile.dart';
import 'package:fireplace/src/widgets/settings/settings_group.dart';
import 'package:fireplace/src/widgets/settings/settings_page.dart';
import 'package:fireplace/src/widgets/settings/settings_tile.dart';

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
    const category = SettingsCategory.appearance;
    final colors = ref.watch(chatBubbleColorsProvider);
    return SettingsPage(
      key: category.pageKey,
      title: category.title,
      children: [
        ...errorRows,
        SettingsGroup(
          footer:
              'The theme is for this device. Your color is part of your '
              'profile, so the people you chat with see it.',
          children: [
            const ThemeModeTile(),
            SettingsTile(
              key: const Key('chatColors'),
              leading: const SettingsCategoryIcon(
                category,
                Icons.palette_outlined,
              ),
              title: 'Your color',
              value: colors.outgoing.label,
              onTap: busy ? null : () => open(const ChatAppearanceScreen()),
            ),
          ],
        ),
      ],
    );
  }
}
