import 'package:flutter/material.dart';
import 'package:fireplace/src/styles/design_tokens.dart';

/// A group's avatar: its name's first letter in a rounded square, so groups
/// are a different shape from people's round avatars (owner's choice, 0050).
class GroupAvatar extends StatelessWidget {
  const GroupAvatar({super.key, required this.name, this.size = 44});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = FireplaceUiTokens.of(context);
    final letter = name.trim().isEmpty
        ? '#'
        : name.trim().characters.first.toUpperCase();
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: t.selectedRow,
          borderRadius: BorderRadius.circular(size * 0.28),
          border: Border.all(color: t.accent.withValues(alpha: .35)),
        ),
        child: Text(
          letter,
          style: TextStyle(
            fontSize: size * 0.42,
            fontWeight: FontWeight.w700,
            color: t.accentText,
          ),
        ),
      ),
    );
  }
}
