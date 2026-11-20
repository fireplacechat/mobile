import 'package:flutter/material.dart';

/// A row's icon: a white glyph in a small rounded square of [color], so a
/// list of rows can be scanned by colour. [SettingsIcon.bare] draws the
/// glyph alone in [color], in the same space, for rows such as Sign out.
class SettingsIcon extends StatelessWidget {
  const SettingsIcon(this.icon, {super.key, required this.color})
    : filled = true;
  const SettingsIcon.bare(this.icon, {super.key, required this.color})
    : filled = false;

  final IconData icon;
  final Color color;
  final bool filled;

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
          child: filled
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    // Lighter at the top, like the avatars.
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color.lerp(color, Colors.white, .14)!, color],
                    ),
                  ),
                  child: Icon(icon, size: 19, color: Colors.white),
                )
              : Icon(icon, size: 24, color: color),
        );
}
