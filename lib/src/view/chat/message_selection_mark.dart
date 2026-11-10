import 'package:flutter/material.dart';
import 'package:fireplace/src/styles/design_tokens.dart';

/// A circular selection mark in the account's accent colour.
class MessageSelectionMark extends StatelessWidget {
  const MessageSelectionMark({super.key, required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = FireplaceUiTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 2, right: 10),
      child: Semantics(
        selected: selected,
        label: 'Select message',
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? t.accent : Colors.transparent,
            border: Border.all(
              color: selected ? t.accent : t.secondaryText,
              width: 1.5,
            ),
          ),
          child: selected
              ? const Icon(Icons.check, size: 16, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}
