import 'package:flutter/material.dart';

import 'package:fireplace/src/model/account/takeover.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/widgets/app_bar.dart';
import 'package:fireplace/src/widgets/page.dart';
import 'package:fireplace/src/widgets/settings_section.dart';

/// Picks how long a new phone waits before it can start fresh (decision
/// 0063). Pops with the choice; the caller saves it.
class LostPhoneWaitScreen extends StatelessWidget {
  const LostPhoneWaitScreen({super.key, required this.selected});
  final LostPhoneWait selected;

  @override
  Widget build(BuildContext context) {
    final t = FireplaceUiTokens.of(context);
    return Scaffold(
      appBar: UiAppBar(context: context, title: const Text('Lost-phone wait')),
      body: UiPageScroll(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 8, 4, 20),
            child: Text(
              'A new phone waits this long before it can take over your '
              'account.',
            ),
          ),
          UiSettingsSection(
            title: 'Wait',
            children: [
              for (final wait in LostPhoneWait.values)
                ListTile(
                  key: Key('wait_${wait.length.inDays}'),
                  title: Text(wait.label),
                  trailing: wait == selected
                      ? Icon(Icons.check_rounded, color: t.accent)
                      : null,
                  onTap: () => Navigator.of(context).pop(wait),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The row that shows the wait and opens the picker.
class LostPhoneWaitTile extends StatelessWidget {
  const LostPhoneWaitTile({
    super.key,
    required this.wait,
    required this.onChanged,
    this.enabled = true,
    this.contentPadding,
  });
  final LostPhoneWait wait;
  final ValueChanged<LostPhoneWait> onChanged;
  final bool enabled;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) => ListTile(
    key: const Key('lostPhoneWait'),
    contentPadding: contentPadding,
    leading: const Icon(Icons.hourglass_empty_rounded),
    title: const Text('Lost-phone wait'),
    subtitle: Text(wait.label),
    trailing: const Icon(Icons.chevron_right),
    onTap: !enabled
        ? null
        : () async {
            final picked = await Navigator.of(context).push<LostPhoneWait>(
              MaterialPageRoute(
                builder: (_) => LostPhoneWaitScreen(selected: wait),
              ),
            );
            if (picked != null && picked != wait) onChanged(picked);
          },
  );
}
