import 'package:flutter/material.dart';

import 'package:fireplace/src/styles/design_tokens.dart';

/// The answers on a Message requests row (issue 248): one filled button for
/// the answer most people give, quieter ones beside it. Compact, so they fit
/// on one line at the usual text size and wrap cleanly when they cannot.
abstract final class RequestButtons {
  static const _padding = EdgeInsets.symmetric(horizontal: 16);
  static const _size = Size(0, 36);

  static ButtonStyle main() => FilledButton.styleFrom(
    minimumSize: _size,
    padding: _padding,
    visualDensity: VisualDensity.compact,
  );

  static ButtonStyle quiet(BuildContext context) => OutlinedButton.styleFrom(
    minimumSize: _size,
    padding: _padding,
    visualDensity: VisualDensity.compact,
    side: BorderSide(color: FireplaceUiTokens.of(context).separator),
  );

  static ButtonStyle danger(BuildContext context) => TextButton.styleFrom(
    minimumSize: _size,
    padding: _padding,
    visualDensity: VisualDensity.compact,
    foregroundColor: FireplaceUiTokens.of(context).danger,
  );
}
