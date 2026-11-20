import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/model/notifications/system_notifications.dart';
import 'package:fireplace/src/model/push/push_notification_service.dart';
import 'package:fireplace/src/view/settings/settings_category.dart';
import 'package:fireplace/src/widgets/settings/settings_group.dart';
import 'package:fireplace/src/widgets/settings/settings_tile.dart';
import 'package:fireplace/src/app/passphrase_lock_providers.dart';

/// Settings → Notifications: alerts while Fireplace is closed, whether they
/// show the sender's name and the message and play the pop, and a shortcut to
/// the system settings (banners, badges, lock screen), which the app cannot
/// change.
/// Whether to word settings for iOS. A provider so tests and renders can
/// choose the wording independently of the machine they run on.
final appleWordingProvider = Provider<bool>((_) => Platform.isIOS);

/// Both platforms use the same choice; iOS decrypts in its native extension.
final notificationPreviewAvailableProvider = Provider<bool>(
  (_) =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS,
);

class PushSettingsSection extends ConsumerStatefulWidget {
  const PushSettingsSection({super.key, required this.service});
  final PushNotificationService service;

  @override
  ConsumerState<PushSettingsSection> createState() => _PushSettingsState();
}

class _PushSettingsState extends ConsumerState<PushSettingsSection>
    with WidgetsBindingObserver {
  PushStatus? _status;
  bool _showName = true;
  bool _sound = true;
  bool _preview = true;
  bool _busy = false;
  String? _error;

  String get _system =>
      ref.read(appleWordingProvider) ? 'iOS Settings' : 'Android settings';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Coming back from the system settings may have changed the permission.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) _load();
  }

  Future<void> _load() async {
    try {
      final status = await widget.service.status();
      final showName = await widget.service.showsName();
      final sound = await widget.service.playsSound();
      final preview = await widget.service.showsPreview();
      if (!mounted) return;
      setState(() {
        _status = status;
        _showName = showName;
        _sound = sound;
        _preview = preview;
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load. Try again.');
      }
    }
  }

  Future<void> _change(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      await _load();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not change. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggle(bool want) => _change(() async {
    if (!want) return widget.service.disable();
    await widget.service.start();
    final status = await widget.service.status();
    // The system no longer shows its prompt once someone said no; only its
    // settings can turn alerts back on.
    if (status == PushStatus.blockedBySystem) {
      await ref.read(systemNotificationsProvider).openSettings();
    } else if (status != PushStatus.on) {
      // Allowed, but the server did not take the registration.
      throw StateError('not registered');
    }
  });

  // Only says something when the person may need to act.
  String? get _subtitle =>
      _error ??
      (_status == PushStatus.blockedBySystem ? 'Off in $_system' : null);

  @override
  Widget build(BuildContext context) {
    final on = _status == PushStatus.on;
    final previews = ref.watch(notificationPreviewAvailableProvider);
    final locked = ref.watch(passphraseLockProvider).value?.on == true;
    const category = SettingsCategory.notifications;
    return SettingsGroup(
      title: 'Notifications',
      children: [
        SwitchListTile(
          key: const Key('pushSwitch'),
          secondary: const SettingsCategoryIcon(
            category,
            Icons.notifications_rounded,
          ),
          title: const Text('Allow notifications'),
          subtitle: _subtitle == null ? null : Text(_subtitle!),
          value: on,
          onChanged: _busy || _status == null ? null : _toggle,
        ),
        SwitchListTile(
          key: const Key('pushShowName'),
          secondary: const SettingsCategoryIcon(category, Icons.person_rounded),
          title: const Text('Show sender’s name'),
          value: _showName,
          onChanged: on && !_busy
              ? (value) => _change(() => widget.service.setShowName(value))
              : null,
        ),
        if (previews)
          SwitchListTile(
            key: const Key('pushPreview'),
            secondary: const SettingsCategoryIcon(category, Icons.chat_rounded),
            title: const Text('Show message preview'),
            // The passphrase lock keeps previews off (decision 0033) and puts
            // this choice back when it is turned off.
            subtitle: locked
                ? const Text('Off while the passphrase lock is on')
                : null,
            value: _preview && !locked,
            onChanged: on && !_busy && !locked
                ? (value) => _change(() => widget.service.setShowPreview(value))
                : null,
          ),
        SwitchListTile(
          key: const Key('pushSound'),
          secondary: const SettingsCategoryIcon(
            category,
            Icons.volume_up_rounded,
          ),
          title: const Text('Notification sound'),
          value: _sound,
          onChanged: on && !_busy
              ? (value) => _change(() => widget.service.setSound(value))
              : null,
        ),
        SettingsTile(
          key: const Key('pushSystemSettings'),
          leading: const SettingsCategoryIcon(category, Icons.tune_rounded),
          title: 'More in $_system',
          trailing: const Icon(Icons.open_in_new),
          onTap: () => ref.read(systemNotificationsProvider).openSettings(),
        ),
      ],
    );
  }
}
