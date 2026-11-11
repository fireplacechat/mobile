import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fireplace/src/model/notifications/app_badge.dart';
import 'package:fireplace/src/model/push/push_notification_service.dart';
import 'package:fireplace/src/widgets/settings_section.dart';

/// Settings → Notifications: alerts while Fireplace is closed, whether they
/// show the sender's name, and a shortcut to the system settings (sounds,
/// banners, badges, lock screen), which the app cannot change itself.
/// Whether to word settings for iOS. A provider so tests and renders can
/// choose the wording independently of the machine they run on.
final appleWordingProvider = Provider<bool>((_) => Platform.isIOS);

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
      if (!mounted) return;
      setState(() {
        _status = status;
        _showName = showName;
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not read notification settings.');
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
        setState(() => _error = 'Could not change notifications. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggle(bool want) => _change(() async {
    if (!want) return widget.service.disable();
    await widget.service.start();
    // The system no longer shows its prompt once someone said no; only its
    // settings can turn alerts back on.
    if (await widget.service.status() == PushStatus.blockedBySystem) {
      await ref.read(systemNotificationsProvider).openSettings();
    }
  });

  String get _subtitle {
    if (_error != null) return _error!;
    return switch (_status) {
      null => 'Loading…',
      PushStatus.on =>
        _showName
            ? 'Shows who wrote, never what they wrote.'
            : 'Shows “New Message” only.',
      PushStatus.off => 'No alerts while Fireplace is closed.',
      PushStatus.blockedBySystem => 'Turned off in $_system. Tap to open them.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final on = _status == PushStatus.on;
    return UiSettingsSection(
      title: 'Notifications',
      children: [
        SwitchListTile(
          key: const Key('pushSwitch'),
          secondary: const Icon(Icons.notifications_outlined),
          title: const Text('Allow notifications'),
          subtitle: Text(_subtitle),
          value: on,
          onChanged: _busy || _status == null ? null : _toggle,
        ),
        SwitchListTile(
          key: const Key('pushShowName'),
          secondary: const Icon(Icons.person_outline),
          title: const Text('Show sender’s name'),
          subtitle: const Text(
            'Off shows “Fireplace” instead of the username. Message text is never sent.',
          ),
          value: _showName,
          onChanged: on && !_busy
              ? (value) => _change(() => widget.service.setShowName(value))
              : null,
        ),
        ListTile(
          key: const Key('pushSystemSettings'),
          leading: const Icon(Icons.tune),
          title: const Text('Sounds, banners and badges'),
          subtitle: Text('Change these in $_system.'),
          trailing: const Icon(Icons.open_in_new),
          onTap: () => ref.read(systemNotificationsProvider).openSettings(),
        ),
      ],
    );
  }
}
