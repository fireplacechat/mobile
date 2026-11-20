import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/app/chat_color_preference.dart';
import 'package:fireplace/src/model/notifications/chat_activity.dart';
import 'package:fireplace/src/view/settings/account_settings_screen.dart';
import 'package:fireplace/src/view/settings/appearance_settings_screen.dart';
import 'package:fireplace/src/view/settings/devices_settings_screen.dart';
import 'package:fireplace/src/view/settings/help_settings_screen.dart';
import 'package:fireplace/src/view/settings/notification_settings_screen.dart';
import 'package:fireplace/src/view/settings/privacy_settings_screen.dart';
import 'package:fireplace/src/view/settings/settings_actions.dart';
import 'package:fireplace/src/view/settings/settings_category.dart';
import 'package:fireplace/src/widgets/settings/settings_group.dart';
import 'package:fireplace/src/widgets/settings/settings_profile_card.dart';

/// Settings: your profile card, then one row per category, each opening its
/// own page (issue 249).
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _opening = false;

  Future<void> _open(SettingsCategory category) async {
    if (_opening) return;
    _opening = true;
    try {
      await Navigator.of(context).push(
        settingsPageRoute(context, switch (category) {
          SettingsCategory.account => const AccountSettingsScreen(),
          SettingsCategory.privacy => const PrivacySettingsScreen(),
          SettingsCategory.notifications => const NotificationSettingsScreen(),
          SettingsCategory.appearance => const AppearanceSettingsScreen(),
          SettingsCategory.devices => const DevicesSettingsScreen(),
          SettingsCategory.help => const HelpSettingsScreen(),
        }),
      );
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = ref.watch(chatBubbleColorsProvider).outgoing.outgoing;
    // Unread counts and mute settings could not be read; the reset is on
    // the Notifications page.
    final attention = !ref.watch(
      chatActivityProvider.select((a) => a.preferencesAvailable),
    );
    return SettingsSessionPage(
      title: 'Settings',
      builder: (s) => [
        SettingsProfileCard(
          key: const Key('settingsProfile'),
          username: s.username,
          color: color,
          onTap: () => _open(SettingsCategory.account),
        ),
        // Help and about sits apart from the settings themselves.
        for (final group in [
          SettingsCategory.values.where((c) => c != SettingsCategory.help),
          [SettingsCategory.help],
        ])
          SettingsGroup(
            children: [
              for (final category in group)
                SettingsCategoryTile(
                  key: category.rowKey,
                  category: category,
                  value: category == SettingsCategory.notifications && attention
                      ? 'Needs attention'
                      : null,
                  onTap: () => _open(category),
                ),
            ],
          ),
      ],
    );
  }
}
