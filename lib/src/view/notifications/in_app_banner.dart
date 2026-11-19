import 'package:flutter/material.dart';

import 'package:fireplace/src/styles/brand/logo.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/widgets/avatar.dart';

/// The card a new message shows while Fireplace is open (issue 233): who
/// wrote, when, and the start of the message, like a system banner.
///
/// With previews off it names nobody: the flame stands in for the avatar and
/// it says only how many messages came.
class InAppBanner extends StatelessWidget {
  const InAppBanner({
    super.key,
    required this.title,
    this.preview,
    this.sender,
    this.senderColor,
    this.count = 1,
  });

  /// The sender's name, or "New message" when previews are off.
  final String title;

  /// The start of the message; null when previews are off.
  final String? preview;

  /// Whose avatar to show; null shows the flame.
  final String? sender;
  final Color? senderColor;

  /// Messages this banner stands for; more than one shows a count.
  final int count;

  @override
  Widget build(BuildContext context) {
    final t = FireplaceUiTokens.of(context);
    final text = Theme.of(context).textTheme;
    final sender = this.sender;
    return Container(
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: t.separator),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .16),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (sender == null)
                _Flame(color: t.accent)
              else
                PersonAvatar(name: sender, size: 42, color: senderColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleSmall?.copyWith(
                              color: t.text,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'now',
                          style: text.bodySmall?.copyWith(
                            color: t.secondaryText,
                          ),
                        ),
                        if (count > 1) ...[
                          const SizedBox(width: 6),
                          _Count(count: count, color: t.accent),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      preview ?? 'Tap to open',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium?.copyWith(
                        color: preview == null ? t.secondaryText : t.text,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Says it can be pushed away, as a system banner does.
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: t.separator,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

class _Flame extends StatelessWidget {
  const _Flame({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: .14),
      ),
      child: const FireplaceLogo(size: 24),
    ),
  );
}

class _Count extends StatelessWidget {
  const _Count({required this.count, required this.color});
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 20),
    height: 20,
    padding: const EdgeInsets.symmetric(horizontal: 6),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      count > 99 ? '99+' : '$count',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
