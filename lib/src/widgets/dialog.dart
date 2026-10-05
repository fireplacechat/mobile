import 'package:flutter/material.dart';
import 'package:fireplace/src/styles/design_tokens.dart';

/// All dialog content, including actions, scrolls on short keyboard viewports.
class UiDialog extends StatelessWidget {
  const UiDialog({
    super.key,
    this.icon,
    this.title,
    this.content,
    this.actions = const [],
  });
  final Widget? icon, title, content;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) {
    final t = FireplaceUiTokens.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      backgroundColor: t.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: t.separator),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (icon != null) ...[
                Center(child: icon!),
                const SizedBox(height: 16),
              ],
              if (title != null) ...[
                Semantics(
                  namesRoute: true,
                  child: DefaultTextStyle(
                    style: Theme.of(context).textTheme.headlineSmall!,
                    child: title!,
                  ),
                ),
                const SizedBox(height: 20),
              ],
              if (content != null)
                DefaultTextStyle(
                  style: Theme.of(context).textTheme.bodyMedium!,
                  child: content!,
                ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 20),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: actions,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
