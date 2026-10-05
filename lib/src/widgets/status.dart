import 'package:flutter/material.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/styles/brand/lockup.dart';

class UiStatus extends StatelessWidget {
  const UiStatus({super.key, required this.label, required this.icon});
  final String label;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: FireplaceUiTokens.of(context).selectedRow,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: FireplaceUiTokens.of(context).accentText, size: 20),
        const SizedBox(width: 8),
        Flexible(child: Text(label)),
      ],
    ),
  );
}

class UiNotice extends StatelessWidget {
  const UiNotice({
    super.key,
    required this.text,
    this.actions = const [],
    this.warning = false,
    this.brandText = false,
  });
  final String text;
  final List<Widget> actions;
  final bool warning;
  final bool brandText;
  @override
  Widget build(BuildContext context) {
    final t = FireplaceUiTokens.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: warning ? t.warningSurface : t.panel,
          border: Border.all(
            color: warning ? t.warningText.withValues(alpha: .2) : t.separator,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (brandText)
              FireplaceBrandText(
                text,
                style: TextStyle(color: warning ? t.warningText : t.text),
              )
            else
              Text(
                text,
                style: TextStyle(color: warning ? t.warningText : t.text),
              ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 4, children: actions),
            ],
          ],
        ),
      ),
    );
  }
}

/// Persistent, announced feedback for an explicit action. No diagnostics or logs.
class UiActionError extends StatelessWidget {
  const UiActionError({super.key, required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline,
            color: FireplaceUiTokens.of(context).danger,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FireplaceBrandText(
              message,
              style: TextStyle(color: FireplaceUiTokens.of(context).danger),
            ),
          ),
        ],
      ),
    ),
  );
}
