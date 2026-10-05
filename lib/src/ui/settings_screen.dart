import 'package:flutter/material.dart';

import 'presentation.dart';
import 'chat_appearance.dart';
import 'legal_links.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../crypto/fingerprint.dart';
import 'account_deletion_screens.dart';
import 'devices_screen.dart';
import '../services/push_notification_service.dart';
import 'recovery_screens.dart';
import 'safety_ui.dart';
import 'design_tokens.dart';
import 'chat_activity.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _busy = false;
  String? _error, _fingerprintFor;
  Future<String>? _fingerprint;
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'That action did not finish. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(Widget page) => _run(() async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => page));
  });
  @override
  Widget build(BuildContext context) {
    final session = ref.watch(appSessionProvider);
    final s = session.value;
    final activity = ref.watch(chatActivityProvider);
    if (s != null && _fingerprintFor != '${s.uid}/${s.device.keys.deviceId}') {
      _fingerprintFor = '${s.uid}/${s.device.keys.deviceId}';
      _fingerprint = identityFingerprint(s.device.identity.publicBytes);
    }
    return Scaffold(
      appBar: UiAppBar(context: context, title: Text('Settings')),
      body: s == null
          ? session.hasError
                ? UiEmptyState(
                    title: 'Could not load your account',
                    message: 'Try again to open Settings.',
                    action: TextButton(
                      onPressed: () => ref.invalidate(appSessionProvider),
                      child: const Text('Try again'),
                    ),
                  )
                : session.isLoading
                ? const Center(child: CircularProgressIndicator())
                : const UiEmptyState(
                    title: 'Sign in to view Settings',
                    message: 'Go back to sign in to your account.',
                  )
          : UiPageScroll(
              children: [
                if (_error != null)
                  UiActionError(
                    key: const Key('settingsError'),
                    message: _error!,
                  ),
                if (!activity.preferencesAvailable)
                  UiSettingsSection(
                    title: 'On this device',
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'Unread counts and notification preferences could not be loaded. In-app notifications are off. Your messages are kept.',
                        ),
                      ),
                      TextButton(
                        key: const Key('resetChatPreferences'),
                        onPressed: _busy
                            ? null
                            : () => _run(() async {
                                final go = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => UiDialog(
                                    title: const Text(
                                      'Reset local preferences?',
                                    ),
                                    content: const Text(
                                      'Unread counts and mute settings on this device will reset. Existing messages count as read and are kept. Notifications return to showing the name and message.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: const Text('Cancel'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: const Text('Reset'),
                                      ),
                                    ],
                                  ),
                                );
                                if (go == true) {
                                  await ref
                                      .read(chatActivityProvider.notifier)
                                      .resetPreferences();
                                }
                              }),
                        child: const Text(
                          'Reset unread and notification preferences',
                        ),
                      ),
                    ],
                  ),
                UiSettingsSection(
                  title: 'Appearance',
                  children: [
                    ListTile(
                      key: const Key('chatColors'),
                      leading: const Icon(Icons.palette_outlined),
                      title: const Text('Chat colors'),
                      subtitle: const Text('Choose your bubble colors'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _busy
                          ? null
                          : () => _open(const ChatAppearanceScreen()),
                    ),
                  ],
                ),
                UiSettingsSection(
                  title: 'About',
                  children: [
                    ListTile(
                      key: const Key('legalLinks'),
                      leading: const Icon(Icons.policy_outlined),
                      title: const Text('Privacy and terms'),
                      subtitle: const Text(
                        'Read the privacy policy and terms of use',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _busy
                          ? null
                          : () => _open(const LegalLinksScreen()),
                    ),
                    ListTile(
                      key: const Key('openLicences'),
                      leading: const Icon(Icons.description_outlined),
                      title: const Text('Open-source licences'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _busy
                          ? null
                          : () => showLicensePage(
                              context: context,
                              applicationName: 'fireplace.',
                            ),
                    ),
                  ],
                ),
                UiSettingsSection(
                  title: 'Account',
                  children: [
                    ListTile(
                      leading: Icon(Icons.person_outline),
                      title: Text('@${s.username}'),
                      subtitle: Text('Your username'),
                    ),
                    ListTile(
                      key: Key('changePassword'),
                      leading: Icon(Icons.password),
                      title: Text('Change password'),
                      onTap: _busy
                          ? null
                          : () => _run(
                              () => showChangePasswordDialog(context, ref),
                            ),
                    ),
                  ],
                ),
                UiSettingsSection(
                  title: 'Privacy and security',
                  children: [
                    FutureBuilder<String>(
                      future: _fingerprint,
                      builder: (_, snap) => ListTile(
                        leading: Icon(Icons.fingerprint),
                        title: Text(
                          snap.data ?? '…',
                          style: TextStyle(fontFamily: 'monospace'),
                        ),
                        subtitle: Text('Your identity fingerprint'),
                      ),
                    ),
                    ListTile(
                      leading: Icon(Icons.phone_android),
                      title: Text(
                        s.device.keys.deviceId,
                        style: TextStyle(fontFamily: 'monospace', fontSize: 13),
                      ),
                      subtitle: Text('This device'),
                    ),
                    ListTile(
                      key: Key('blockedPeople'),
                      leading: Icon(Icons.block),
                      title: Text('Blocked people'),
                      trailing: Icon(Icons.chevron_right),
                      onTap: _busy
                          ? null
                          : () => _open(const BlockedUsersScreen()),
                    ),
                  ],
                ),
                UiSettingsSection(
                  title: 'Devices and recovery',
                  children: [
                    ListTile(
                      key: Key('devices'),
                      leading: Icon(Icons.devices),
                      title: Text('Your devices'),
                      trailing: Icon(Icons.chevron_right),
                      onTap: _busy ? null : () => _open(const DevicesScreen()),
                    ),
                    ListTile(
                      key: Key('recoveryKey'),
                      leading: Icon(Icons.key),
                      title: Text('Recovery key'),
                      subtitle: Text(
                        'Restore your identity, not past messages',
                      ),
                      trailing: Icon(Icons.chevron_right),
                      onTap: _busy
                          ? null
                          : () => _open(const RecoveryKeyScreen()),
                    ),
                    ListTile(
                      key: Key('linkDevice'),
                      leading: Icon(Icons.add_to_home_screen),
                      title: Text('Link a new device'),
                      trailing: Icon(Icons.chevron_right),
                      onTap: _busy
                          ? null
                          : () => _open(const LinkNewDeviceScreen()),
                    ),
                  ],
                ),
                UiSettingsSection(
                  title: 'In-app notifications',
                  children: [
                    SwitchListTile(
                      key: const Key('notificationPreviews'),
                      title: const Text('Show message text'),
                      subtitle: const Text(
                        'On shows the name and message. Off shows “New message” only. Applies while the app is open; previews stay on this device.',
                      ),
                      value: ref.watch(chatActivityProvider).previewText,
                      onChanged: _busy || !activity.preferencesAvailable
                          ? null
                          : (value) => _run(
                              () => ref
                                  .read(chatActivityProvider.notifier)
                                  .previews(value),
                            ),
                    ),
                  ],
                ),
                if (pushEnabled && s.pushNotifications != null)
                  UiSettingsSection(
                    title: 'Notifications',
                    children: [_PushTile(service: s.pushNotifications!)],
                  ),
                UiSettingsSection(
                  title: 'Account actions',
                  children: [
                    ListTile(
                      key: Key('deleteAccountTile'),
                      leading: Icon(
                        Icons.delete_forever,
                        color: FireplaceUiTokens.of(context).danger,
                      ),
                      title: Text(
                        'Delete account',
                        style: TextStyle(
                          color: FireplaceUiTokens.of(context).danger,
                        ),
                      ),
                      subtitle: Text(
                        'Delete your account; received copies stay with others',
                      ),
                      onTap: _busy
                          ? null
                          : () => _open(const DeleteAccountScreen()),
                    ),
                    ListTile(
                      key: Key('signOut'),
                      leading: Icon(
                        Icons.logout,
                        color: FireplaceUiTokens.of(context).danger,
                      ),
                      title: Text('Sign out'),
                      subtitle: Text(
                        'Keys and history stay on this device so you can sign back in.',
                      ),
                      onTap: _busy
                          ? null
                          : () => _run(() async {
                              await ref.read(authServiceProvider).signOut();
                              if (context.mounted) {
                                Navigator.of(context)
                                    .popUntil((r) => r.isFirst);
                              }
                            }),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

/// Opt-in switch; the OS permission prompt only appears when the user turns it on.
class _PushTile extends StatefulWidget {
  const _PushTile({required this.service});
  final PushNotificationService service;
  @override
  State<_PushTile> createState() => _PushTileState();
}

class _PushTileState extends State<_PushTile> {
  bool _on = false;
  bool _loading = true;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.service
        .isOn()
        .then((v) {
          if (mounted) {
            setState(() {
              _on = v;
              _loading = false;
            });
          }
        })
        .catchError((Object _) {
          if (mounted) {
            setState(() {
              _loading = false;
              _error = 'Could not read notification preference.';
            });
          }
        });
  }

  Future<void> _toggle(bool want) async {
    if (_busy || _loading) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (want) {
        await widget.service.start();
      } else {
        await widget.service.disable();
      }
      final now = await widget.service.isOn();
      if (mounted) setState(() => _on = now);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not change notifications. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SwitchListTile(
    key: Key('pushSwitch'),
    secondary: Icon(Icons.notifications_outlined),
    title: Text('Notifications'),
    subtitle: Text(
      _loading ? 'Loading preference…' : _error ?? 'A generic alert for new messages. It never shows who wrote or what.',
    ),
    value: _on,
    onChanged: _busy || _loading ? null : _toggle,
  );
}
