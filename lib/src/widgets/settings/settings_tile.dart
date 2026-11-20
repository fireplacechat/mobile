import 'package:flutter/material.dart';

import 'package:fireplace/src/styles/design_tokens.dart';

/// One row of a [SettingsGroup]: an icon, a title, the current value where
/// it helps ("Theme  Light"), and a chevron when the row opens something.
///
/// The value sits at the end of the title's line while both fit, and moves
/// under the title when they do not (a narrow phone, large text), so neither
/// is squeezed into a sliver.
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.title,
    this.leading,
    this.value,
    this.titleColor,
    this.onTap,
    this.onLongPress,
    this.trailing,
    this.chevron = true,
    this.contentPadding,
  });

  final String title;
  final Widget? leading;
  final String? value;
  final Color? titleColor;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// In place of the chevron, such as an "open elsewhere" icon.
  final Widget? trailing;

  /// Whether the row shows a chevron; off for rows that only show a value.
  final bool chevron;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    final t = FireplaceUiTokens.of(context);
    final label = Text(
      title,
      style: titleColor == null ? null : TextStyle(color: titleColor),
    );
    return ListTile(
      leading: leading,
      contentPadding: contentPadding,
      title: value == null
          ? label
          : SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                children: [
                  label,
                  Text(
                    value!,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: t.secondaryText),
                  ),
                ],
              ),
            ),
      trailing: trailing ?? (chevron ? const Icon(Icons.chevron_right) : null),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}
