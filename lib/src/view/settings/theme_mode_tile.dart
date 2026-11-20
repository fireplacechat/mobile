import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/theme_preference.dart';
import 'package:fireplace/src/view/settings/settings_category.dart';
import 'package:fireplace/src/view/settings/theme_screen.dart';
import 'package:fireplace/src/widgets/settings/settings_tile.dart';

class ThemeModeTile extends ConsumerWidget {
  const ThemeModeTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preference = ref.watch(themeModeProvider);
    final mode = preference.value ?? ThemeMode.system;
    final dark = mode == ThemeMode.system
        ? Theme.of(context).brightness == Brightness.dark
        : mode == ThemeMode.dark;
    return SettingsTile(
      key: const Key('themeMode'),
      leading: const SettingsCategoryIcon(
        SettingsCategory.appearance,
        Icons.brightness_6_rounded,
      ),
      title: 'Theme',
      value: dark ? 'Dark' : 'Light',
      onTap: preference.isLoading
          ? null
          : () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const ThemeScreen()),
            ),
    );
  }
}
