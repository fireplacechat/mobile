import 'package:flutter/material.dart';

import 'package:fireplace/src/widgets/settings/settings_icon.dart';
import 'package:fireplace/src/widgets/settings/settings_tile.dart';

/// The pages the main Settings page opens (issue 249).
enum SettingsCategory {
  account('Account', Icons.person_outline_rounded),
  privacy('Privacy and security', Icons.lock_outline_rounded),
  notifications('Notifications and sounds', Icons.notifications_none_rounded),
  appearance('Appearance', Icons.palette_outlined),
  devices('Devices and recovery', Icons.devices_outlined),
  help('Help and about', Icons.help_outline_rounded);

  const SettingsCategory(this.title, this.icon);
  final String title;
  final IconData icon;

  /// The row on the main page that opens this category.
  Key get rowKey => Key('settings_$name');

  /// The page itself.
  Key get pageKey => Key('settingsPage_$name');
}

/// A category's row on the main Settings page.
class SettingsCategoryTile extends StatelessWidget {
  const SettingsCategoryTile({
    super.key,
    required this.category,
    required this.onTap,
    this.value,
  });

  final SettingsCategory category;
  final VoidCallback onTap;
  final String? value;

  @override
  Widget build(BuildContext context) => SettingsTile(
    leading: SettingsIcon(category.icon),
    title: category.title,
    value: value,
    onTap: onTap,
  );
}

/// An icon for the rows of a category's page.
class SettingsCategoryIcon extends StatelessWidget {
  const SettingsCategoryIcon(this.category, this.icon, {super.key});
  final SettingsCategory category;
  final IconData icon;

  @override
  Widget build(BuildContext context) => SettingsIcon(icon);
}
