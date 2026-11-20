import 'package:flutter/material.dart';

import 'package:fireplace/src/styles/chat_colors.dart';
import 'package:fireplace/src/widgets/settings/settings_icon.dart';
import 'package:fireplace/src/widgets/settings/settings_tile.dart';

/// The pages the main Settings page opens (issue 249). Each has its own
/// colour from the chat colours, so the list can be scanned at a glance; a
/// white glyph stays readable on every one of them, in light and dark.
enum SettingsCategory {
  account('Account', Icons.person_rounded, ChatBubbleColor.ocean),
  privacy('Privacy and security', Icons.lock_rounded, ChatBubbleColor.forest),
  notifications(
    'Notifications and sounds',
    Icons.notifications_rounded,
    ChatBubbleColor.berry,
  ),
  appearance('Appearance', Icons.palette_rounded, ChatBubbleColor.plum),
  devices('Devices and recovery', Icons.devices_rounded, ChatBubbleColor.smoke),
  help('Help and about', Icons.help_rounded, ChatBubbleColor.honey);

  const SettingsCategory(this.title, this.icon, this.color);
  final String title;
  final IconData icon;
  final ChatBubbleColor color;

  /// The fill behind this category's icons, on the main page and its own.
  Color get tint => color.outgoing;

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
    leading: SettingsIcon(category.icon, color: category.tint),
    title: category.title,
    value: value,
    onTap: onTap,
  );
}

/// An icon in a category's colour, for the rows of that category's page.
class SettingsCategoryIcon extends StatelessWidget {
  const SettingsCategoryIcon(this.category, this.icon, {super.key});
  final SettingsCategory category;
  final IconData icon;

  @override
  Widget build(BuildContext context) =>
      SettingsIcon(icon, color: category.tint);
}
