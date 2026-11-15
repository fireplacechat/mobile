import 'dart:math' as math;

import 'package:flutter/material.dart';

class ComposerNote extends StatelessWidget {
  const ComposerNote({super.key, required this.text, this.action});
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => ColoredBox(
    // The note's colour runs to the bottom of the screen, as the bar's does.
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: math.max(
            72,
            (MediaQuery.sizeOf(context).height -
                    MediaQuery.viewInsetsOf(context).bottom) *
                .3,
          ),
        ),
        child: SingleChildScrollView(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(text),
                if (action != null)
                  Align(alignment: Alignment.centerRight, child: action!),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
