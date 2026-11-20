import 'package:flutter/material.dart';

import 'package:fireplace/src/styles/design_tokens.dart';

/// A row's icon: an outline glyph in the text colour, with no tile behind
/// it, as messengers' settings commonly draw them (the owner asked for
/// plain icons). [SettingsIcon.bare] draws it in [color] instead, for rows
/// such as Sign out.
class SettingsIcon extends StatelessWidget {
  const SettingsIcon(this.icon, {super.key}) : color = null;
  const SettingsIcon.bare(this.icon, {super.key, required Color this.color});

  final IconData icon;

  /// The glyph's colour when it is not the text colour.
  final Color? color;

  /// The icon's width; rows line their text up after it.
  static const double size = 24;

  /// Text this large (a narrow phone at 200%) needs the row's width more
  /// than the icon, which only repeats the words beside it.
  static bool hiddenAt(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(10) >= 16;

  @override
  Widget build(BuildContext context) => hiddenAt(context)
      ? const SizedBox.shrink()
      : Icon(
          icon,
          size: size,
          color: color ?? FireplaceUiTokens.of(context).text,
        );
}
