import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/widgets/settings/settings_icon.dart';

/// Rows in one rounded card with hairline dividers, an optional heading
/// above it and an optional short note below it, in small text.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    required this.children,
    this.title,
    this.footer,
  });

  final List<Widget> children;
  final String? title;
  final String? footer;

  /// Where a row's text starts, so dividers begin under the text, not the
  /// icon.
  static const double textStart =
      _padding + SettingsIcon.size + _gap; // 16 + 30 + 14
  static const double _padding = 16, _gap = 14;

  @override
  Widget build(BuildContext context) {
    final t = FireplaceUiTokens.of(context);
    final small = Theme.of(context).textTheme.bodySmall;
    final hairline = math.max(.5, 1 / MediaQuery.devicePixelRatioOf(context));
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(_padding, 0, _padding, 8),
              child: Semantics(
                header: true,
                child: Text(
                  title!,
                  style: small?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          Material(
            color: t.panel,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: ListTileTheme.merge(
              contentPadding: const EdgeInsetsDirectional.only(
                start: _padding,
                end: 12,
              ),
              minLeadingWidth: SettingsIcon.size,
              horizontalTitleGap: _gap,
              minVerticalPadding: 10,
              // Square, so a press fills the row inside the rounded card.
              shape: const RoundedRectangleBorder(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: hairline,
                        thickness: hairline,
                        indent: textStart,
                        color: t.separator,
                      ),
                    children[i],
                  ],
                ],
              ),
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(_padding, 8, _padding, 0),
              child: Text(footer!, style: small),
            ),
        ],
      ),
    );
  }
}
