import 'package:flutter/material.dart';
import 'package:fireplace/src/db/message_quote.dart';
import 'package:fireplace/src/model/chat/message_format.dart';
import 'package:fireplace/src/styles/design_tokens.dart';

class MessageQuotePreview extends StatelessWidget {
  const MessageQuotePreview({
    super.key,
    required this.quote,
    required this.author,
    this.foreground,
    this.onTap,
  });
  final MessageQuote quote;
  final String author;
  final Color? foreground;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = FireplaceUiTokens.of(context);
    final color = foreground ?? tokens.text;
    return Semantics(
      button: onTap != null,
      label: 'Quoted message',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .08),
            border: Border(
              left: BorderSide(color: foreground ?? tokens.accent, width: 3),
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                quote.unavailable
                    ? 'Original message unavailable'
                    : displayMessage(quote.body).plain,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontSize: 14, height: 1.2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
