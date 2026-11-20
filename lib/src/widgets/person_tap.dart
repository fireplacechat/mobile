import 'package:flutter/material.dart';

import 'package:fireplace/src/styles/design_tokens.dart';

/// The shade laid over a person's avatar or name while it is pressed: slight,
/// and the same in every place that opens a profile (issue 245).
WidgetStateProperty<Color?> _shade(BuildContext context) {
  final text = FireplaceUiTokens.of(context).text;
  return WidgetStateProperty.resolveWith((states) {
    if (states.contains(WidgetState.pressed)) return text.withAlpha(36);
    if (states.contains(WidgetState.focused)) return text.withAlpha(30);
    if (states.contains(WidgetState.hovered)) return text.withAlpha(16);
    return null;
  });
}

/// A person's avatar that opens their profile. Only the circle responds, and
/// only the circle is shaded while pressed. With no [onTap] it is the plain
/// avatar.
class TappableAvatar extends StatelessWidget {
  const TappableAvatar({super.key, required this.child, required this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (onTap == null) return child;
    // Ink paints under a widget's own pixels, and an avatar is a solid disc,
    // so the pressable layer lies on top of it.
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              customBorder: const CircleBorder(),
              splashFactory: NoSplash.splashFactory,
              overlayColor: _shade(context),
              onTap: onTap,
            ),
          ),
        ),
      ],
    );
  }
}

/// A person's name that opens their profile. The shade is a soft rounded
/// patch a few pixels round the words, not the space beside them; put it
/// where it can be as narrow as its text (not in an Expanded).
class TappableName extends StatelessWidget {
  const TappableName({super.key, required this.child, required this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (onTap == null) return child;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        splashFactory: NoSplash.splashFactory,
        overlayColor: _shade(context),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: child,
        ),
      ),
    );
  }
}
