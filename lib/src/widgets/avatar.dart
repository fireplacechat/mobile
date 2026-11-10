import 'package:flutter/material.dart';
import 'package:fireplace/src/styles/design_tokens.dart';

/// Up to two initials: one per word, so a single-word username shows one.
String avatarInitials(String name) {
  final words = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.isEmpty) return '?';
  return [
    words.first.characters.first,
    if (words.length > 1) words.last.characters.first,
  ].join().toUpperCase();
}

/// Initials on the brand orange. There are no profile photos.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({super.key, required this.name, this.size = 44});
  final String name;
  final double size;
  @override
  Widget build(BuildContext context) {
    final t = FireplaceUiTokens.of(context);
    final initials = avatarInitials(name);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // Lighter at the top, like a lit surface; white stays above 3:1.
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color.lerp(t.accent, Colors.white, .18)!, t.accent],
          ),
        ),
        child: Text(
          initials,
          maxLines: 1,
          softWrap: false,
          // The initial is part of the picture and scales with the circle.
          textScaler: TextScaler.noScaling,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: size * (initials.characters.length > 1 ? .37 : .43),
            height: 1,
            fontWeight: FontWeight.w700,
            leadingDistribution: TextLeadingDistribution.even,
          ),
        ),
      ),
    );
  }
}
