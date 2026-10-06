import 'package:flutter/material.dart';
import 'package:fireplace/src/model/push/push_notification_service.dart';

/// Opt-in switch; the OS permission prompt only appears when the user turns it on.
class PushTile extends StatefulWidget {
  const PushTile({super.key, required this.service});
  final PushNotificationService service;
  @override
  State<PushTile> createState() => _PushTileState();
}

class _PushTileState extends State<PushTile> {
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
