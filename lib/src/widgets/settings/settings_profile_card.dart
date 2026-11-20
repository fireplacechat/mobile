import 'package:flutter/material.dart';

import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/widgets/avatar.dart';

/// The top of Settings: your avatar in your colour, your @username, and a
/// chevron to the page that holds the account's settings.
class SettingsProfileCard extends StatelessWidget {
  const SettingsProfileCard({
    super.key,
    required this.username,
    required this.color,
    required this.onTap,
  });

  final String username;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = FireplaceUiTokens.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Material(
        color: t.panel,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: MergeSemantics(
          child: Semantics(
            button: true,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 12, 14),
                child: Row(
                  children: [
                    PersonAvatar(name: username, size: 60, color: color),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '@$username',
                            style: text.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Your username',
                            style: text.bodyMedium?.copyWith(
                              color: t.secondaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.chevron_right, color: t.secondaryText),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
