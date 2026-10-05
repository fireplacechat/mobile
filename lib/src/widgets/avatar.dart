import 'package:flutter/material.dart';
import 'package:fireplace/src/styles/design_tokens.dart';

class PersonAvatar extends StatelessWidget {
  const PersonAvatar({super.key, required this.name, this.size = 44});
  final String name;
  final double size;
  @override
  Widget build(BuildContext context) {
    final t = FireplaceUiTokens.of(context);
    final value = name.trim();
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: t.selectedRow,
          border: Border.all(color: t.separator),
          borderRadius: BorderRadius.circular(size * .36),
        ),
        child: Text(
          value.isEmpty ? '?' : value.characters.first.toUpperCase(),
          style: TextStyle(color: t.text, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
