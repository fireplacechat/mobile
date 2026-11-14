import 'package:flutter/material.dart';
import 'package:fireplace/src/model/chat/message_format.dart';
import 'package:fireplace/src/styles/design_tokens.dart';

/// The bar above the composer while replying: a coloured tab at the leading
/// edge, the name of the person being replied to in the same colour, one line
/// of their message, and a button to cancel.
///
/// The colour is that person's own: in a group the colour they chose, in a 1:1
/// chat the colour their messages have on this phone, and this account's
/// primary colour when replying to oneself.
class ReplyPanel extends StatelessWidget {
  const ReplyPanel({
    super.key,
    required this.author,
    required this.body,
    required this.color,
    required this.onCancel,
    this.unavailable = false,
  });
  final String author, body;

  /// The tab and the name. A shade that reads as text on the page.
  final Color color;
  final VoidCallback onCancel;

  /// The original has gone (deleted) since the reply was started.
  final bool unavailable;

  static const double tab = 4;

  @override
  Widget build(BuildContext context) {
    final t = FireplaceUiTokens.of(context);
    return Semantics(
      container: true,
      label: 'Replying to $author',
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // From the screen's edge, the full height of the bar.
            ColoredBox(
              key: const Key('replyPanelTab'),
              color: color,
              child: const SizedBox(width: tab),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      author,
                      key: const Key('replyPanelAuthor'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: 16,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      unavailable
                          ? 'Original message unavailable'
                          : displayMessage(body).plain,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.text,
                        fontSize: 15,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Center(
              child: IconButton(
                key: const Key('cancelReply'),
                tooltip: 'Cancel reply',
                onPressed: onCancel,
                icon: const Icon(Icons.cancel_outlined),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
