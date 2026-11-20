import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/model/notifications/chat_activity.dart';
import 'package:fireplace/src/model/push/push_notification_service.dart';
import 'package:fireplace/src/model/settings/send_sound_preference.dart';
import 'package:fireplace/src/view/settings/push_settings.dart';
import 'package:fireplace/src/view/settings/settings_actions.dart';
import 'package:fireplace/src/view/settings/settings_category.dart';
import 'package:fireplace/src/widgets/dialog.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/widgets/settings/settings_group.dart';
import 'package:fireplace/src/widgets/settings/settings_tile.dart';

/// Settings → Notifications and sounds: alerts while Fireplace is closed,
/// banners and sounds while it is open, and the reset for unread counts
/// and mute settings that could not be read.
class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends ConsumerState<NotificationSettingsScreen>
    with SettingsActions {
  Future<void> _reset() => run(() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => UiDialog(
        title: const Text('Reset local preferences?'),
        content: const Text(
          'Unread counts and mute settings on this device will reset. '
          'Existing messages count as read and are kept. Notifications '
          'return to showing the name and message.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (go == true) {
      await ref.read(chatActivityProvider.notifier).resetPreferences();
    }
  });

  @override
  Widget build(BuildContext context) {
    const category = SettingsCategory.notifications;
    final activity = ref.watch(chatActivityProvider);
    return SettingsSessionPage(
      key: category.pageKey,
      title: category.title,
      builder: (s) => [
        ...errorRows,
        if (!activity.preferencesAvailable)
          SettingsGroup(
            title: 'On this device',
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Unread counts and notification preferences could not be '
                  'loaded. In-app notifications are off. Your messages are '
                  'kept.',
                ),
              ),
              SettingsTile(
                key: const Key('resetChatPreferences'),
                leading: const SettingsCategoryIcon(
                  category,
                  Icons.restart_alt_rounded,
                ),
                title: 'Reset unread and notification preferences',
                titleColor: FireplaceUiTokens.of(context).accentText,
                chevron: false,
                onTap: busy ? null : _reset,
              ),
            ],
          ),
        if (pushEnabled && s.pushNotifications != null)
          PushSettingsSection(service: s.pushNotifications!),
        SettingsGroup(
          title: 'In the app',
          footer:
              'While Fireplace is open, a banner shows who wrote and what '
              'they said. Turned off, it says only “New message”.',
          children: [
            SwitchListTile(
              key: const Key('notificationPreviews'),
              secondary: const SettingsCategoryIcon(
                category,
                Icons.chat_bubble_outline_rounded,
              ),
              title: const Text('In-App Notifications'),
              value: activity.previewText,
              onChanged: busy || !activity.preferencesAvailable
                  ? null
                  : (value) => run(
                      () => ref
                          .read(chatActivityProvider.notifier)
                          .previews(value),
                    ),
            ),
            SwitchListTile(
              key: const Key('sendSound'),
              secondary: const SettingsCategoryIcon(
                category,
                Icons.send_outlined,
              ),
              title: const Text('Send sound'),
              value: ref.watch(sendSoundProvider).value ?? true,
              onChanged: busy
                  ? null
                  : (value) => run(
                      () => ref.read(sendSoundProvider.notifier).setOn(value),
                    ),
            ),
          ],
        ),
      ],
    );
  }
}
