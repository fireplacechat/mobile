import 'package:flutter/material.dart';

import 'package:fireplace/src/styles/design_tokens.dart';

/// A row's icon: the glyph in the text colour on a small, soft rounded
/// square, the same on every row (the owner preferred this to a colour per
/// category). [SettingsIcon.bare] draws the glyph alone in [color], in the
/// same space, for rows such as Sign out.
class SettingsIcon extends StatelessWidget {
  const SettingsIcon(this.icon, {super.key}) : color = null;
  const SettingsIcon.bare(this.icon, {super.key, required Color this.color});

  final IconData icon;

  /// The bare glyph's colour; null for the tiled icon.
  final Color? color;

  /// The square's side; rows line their text up after it.
  static const double size = 30;

  /// Text this large (a narrow phone at 200%) needs the row's width more
  /// than the icon, which only repeats the words beside it.
  static bool hiddenAt(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(10) >= 16;

  @override
  Widget build(BuildContext context) => hiddenAt(context)
      ? const SizedBox.shrink()
      : SizedBox.square(
          dimension: size,
          child: switch (color) {
            final bare? => Icon(icon, size: 24, color: bare),
            null => DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: FireplaceUiTokens.of(context).selectedRow,
              ),
              child: Icon(
                icon,
                size: 19,
                color: FireplaceUiTokens.of(context).text,
              ),
            ),
          },
        );
}
