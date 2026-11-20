import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/model/notifications/chat_activity.dart';
import 'package:fireplace/src/model/push/push_notification_service.dart';
import 'package:fireplace/src/model/settings/send_sound_preference.dart';
import 'package:fireplace/src/view/settings/push_settings.dart';
import 'package:fireplace/src/view/settings/settings_actions.dart';
import 'package:fireplace/src/view/settings/settings_category.dart';
import 'package:fireplace/src/widgets/dialog.dart';
import 'package:fireplace/src/widgets/settings_section.dart';

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
    final activity = ref.watch(chatActivityProvider);
    return SettingsSessionPage(
      key: SettingsCategory.notifications.pageKey,
      title: SettingsCategory.notifications.title,
      builder: (s) => [
        ...errorRows,
        if (!activity.preferencesAvailable)
          UiSettingsSection(
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
              TextButton(
                key: const Key('resetChatPreferences'),
                onPressed: busy ? null : _reset,
                child: const Text('Reset unread and notification preferences'),
              ),
            ],
          ),
        if (pushEnabled && s.pushNotifications != null)
          PushSettingsSection(service: s.pushNotifications!),
        UiSettingsSection(
          title: 'In the app',
          children: [
            SwitchListTile(
              key: const Key('notificationPreviews'),
              secondary: const Icon(Icons.chat_bubble_outline),
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
              secondary: const Icon(Icons.send_outlined),
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
