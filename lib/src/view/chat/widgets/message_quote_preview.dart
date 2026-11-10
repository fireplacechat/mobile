import 'package:flutter/material.dart';
import 'package:fireplace/src/db/message_quote.dart';
import 'package:fireplace/src/model/chat/message_format.dart';
import 'package:fireplace/src/styles/design_tokens.dart';

/// The quoted message inside a reply: a tinted panel with a stripe at its
/// leading edge, the author's name and up to two lines of the original.
///
/// It is as wide as its own text needs and no wider, so a short reply to a
/// short message stays a small bubble; the bubble stretches it to match a
/// longer reply.
class MessageQuotePreview extends StatelessWidget {
  const MessageQuotePreview({
    super.key,
    required this.quote,
    required this.author,
    this.foreground,
    this.bubble,
    this.outgoing = false,
    this.onTap,
  });
  final MessageQuote quote;
  final String author;
  final Color? foreground;

  /// The colour of the bubble this sits in. Null outside a bubble, such as
  /// above the composer.
  final Color? bubble;

  /// Whether that bubble is one's own message.
  final bool outgoing;
  final VoidCallback? onTap;

  static const double stripe = 4;
  static const double radius = 10;

  @override
  Widget build(BuildContext context) {
    final tokens = FireplaceUiTokens.of(context);
    final onBubble = foreground ?? tokens.text;
    final base = bubble;
    // In one's own coloured bubble the panel is a pale wash of that colour
    // with dark text; in a received bubble it is a slightly stronger tone of
    // the bubble with the bubble's own text colour.
    final washed = base != null && outgoing;
    final panel = base == null
        ? onBubble.withValues(alpha: .08)
        : washed
        ? Color.alphaBlend(Colors.white.withValues(alpha: .45), base)
        : Color.alphaBlend(onBubble.withValues(alpha: .14), base);
    final ink = washed ? FireplaceUiTokens.light.text : onBubble;
    final line = base == null
        ? tokens.accent
        : washed
        ? Colors.white.withValues(alpha: .85)
        : onBubble.withValues(alpha: .45);
    return Semantics(
      button: onTap != null,
      label: 'Quoted message',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: ColoredBox(
            color: panel,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ColoredBox(
                    color: line,
                    child: const SizedBox(width: stripe),
                  ),
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: ink,
                              fontSize: 13,
                              height: 1.3,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            quote.unavailable
                                ? 'Original message unavailable'
                                : displayMessage(quote.body).plain,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: ink,
                              fontSize: 15,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
