import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/styles/design_tokens.dart';
import 'package:fireplace/src/view/chat/message_actions.dart';
import 'package:fireplace/src/view/chat/message_menu_parts.dart';
import 'package:fireplace/src/view/chat/message_widgets.dart';

/// What holding a conversation in the chat list opens: the page blurs, the
/// end of the conversation shows as a preview, and its actions are listed
/// underneath. The list is the one a held message opens (label, icon at the
/// trailing edge, hairlines), so the two menus look the same.
///
/// Completes with the id of the chosen action, or null. The caller acts on it
/// once the menu has closed.
Future<String?> showChatRowMenu(
  BuildContext context, {
  required String title,
  required List<ChatRowAction> actions,
  List<LocalMessage> messages = const [],
}) => Navigator.of(context, rootNavigator: true).push<String>(
  PageRouteBuilder<String>(
    opaque: false,
    barrierDismissible: true,
    barrierColor: Colors.transparent,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (context, animation, _) => _ChatRowMenu(
      animation: animation,
      title: title,
      actions: actions,
      messages: messages,
    ),
  ),
);

/// One row of the menu.
class ChatRowAction {
  const ChatRowAction({
    required this.id,
    required this.label,
    required this.icon,
    this.destructive = false,
  });
  final String id, label;
  final IconData icon;
  final bool destructive;
}

class _ChatRowMenu extends StatelessWidget {
  const _ChatRowMenu({
    required this.animation,
    required this.title,
    required this.actions,
    required this.messages,
  });
  final Animation<double> animation;
  final String title;
  final List<ChatRowAction> actions;
  final List<LocalMessage> messages;

  /// How many of the newest messages the preview holds at most; the card
  /// shows as many of them as fit.
  static const previewMessages = 8;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = FireplaceUiTokens.of(context);
    final media = MediaQuery.of(context);
    final scrim = theme.brightness == Brightness.dark
        ? const Color(0x33FFFFFF)
        : const Color(0x33000000);
    final shown = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeIn,
    );
    final recent = messages.length > previewMessages
        ? messages.sublist(messages.length - previewMessages)
        : messages;
    void close([String? id]) => Navigator.of(context).pop(id);
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): close},
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: close,
              child: FadeTransition(
                opacity: shown,
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: ColoredBox(color: scrim),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: SafeArea(
              minimum: const EdgeInsets.all(MessageMenuMetrics.edge),
              child: FadeTransition(
                opacity: shown,
                child: ScaleTransition(
                  scale: Tween(begin: .94, end: 1.0).animate(shown),
                  alignment: Alignment.topLeft,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Flexible(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: media.size.height * .5,
                          ),
                          child: _Preview(title: title, messages: recent),
                        ),
                      ),
                      const SizedBox(height: MessageMenuMetrics.gap),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            MessageMenuMetrics.menuRadius,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x33000000),
                              blurRadius: 64,
                              offset: Offset(0, 32),
                            ),
                          ],
                        ),
                        child: Material(
                          key: const Key('chatRowMenu'),
                          color: tokens.panel,
                          borderRadius: BorderRadius.circular(
                            MessageMenuMetrics.menuRadius,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: SizedBox(
                            width: MessageMenuMetrics.menuWidth,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final (i, action) in actions.indexed)
                                  MessageMenuRow(
                                    action: MessageAction(
                                      id: action.id,
                                      label: action.label,
                                      icon: action.icon,
                                      destructive: action.destructive,
                                      onSelected: () {},
                                    ),
                                    autofocus: i == 0,
                                    divider: i < actions.length - 1,
                                    onPressed: () => close(action.id),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The end of the conversation, as it looks when open: the name, then the
/// newest messages. It is a picture: nothing in it can be pressed.
class _Preview extends StatelessWidget {
  const _Preview({required this.title, required this.messages});
  final String title;
  final List<LocalMessage> messages;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = FireplaceUiTokens.of(context);
    return Material(
      key: const Key('chatRowPreview'),
      color: theme.scaffoldBackgroundColor,
      borderRadius: BorderRadius.circular(MessageMenuMetrics.menuRadius),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(
            color: tokens.panel,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: tokens.text,
                ),
              ),
            ),
          ),
          if (messages.isNotEmpty)
            Flexible(
              child: IgnorePointer(
                child: ExcludeSemantics(
                  // Newest at the bottom; older ones are cut off at the top.
                  child: SingleChildScrollView(
                    reverse: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final message in messages)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: MessageBubble(
                              key: ValueKey('chatRowPreview-${message.id}'),
                              message: message,
                              preview: true,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
