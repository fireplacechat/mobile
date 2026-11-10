import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/db/message_quote.dart';
import 'package:fireplace/src/model/chat/message_compose_target.dart';
import 'package:fireplace/src/model/chat/message_limits.dart';
import 'package:fireplace/src/view/chat/widgets/message_quote_preview.dart';

class MessageComposerContext extends ConsumerStatefulWidget {
  const MessageComposerContext({
    super.key,
    required this.chatId,
    required this.name,
    required this.builder,
  });
  final String chatId, name;
  final Widget Function(BuildContext, FocusNode, Widget?) builder;
  @override
  ConsumerState<MessageComposerContext> createState() =>
      _MessageComposerContextState();
}

class _MessageComposerContextState
    extends ConsumerState<MessageComposerContext> {
  final _focus = FocusNode();
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = messageComposeProvider(widget.chatId);
    ref.listen(provider, (_, next) {
      if (next != null) _focus.requestFocus();
    });
    final target = ref.watch(provider);
    final uid = ref.watch(appSessionProvider.select((s) => s.value?.uid));
    final messages = ref.watch(messagesProvider(widget.chatId)).value;
    final live = messages?.where((m) => m.id == target?.message.id).firstOrNull;
    return widget.builder(
      context,
      _focus,
      target == null
          ? null
          : Row(
              key: const Key('replyComposerPreview'),
              children: [
                Expanded(
                  child: MessageQuotePreview(
                    quote: MessageQuote(
                      targetId: target.message.id,
                      senderUid: target.message.senderUid,
                      body: clipMessage(live?.body ?? '', 1024),
                      unavailable: live == null || live.remotelyDeleted,
                    ),
                    author: target.message.senderUid == uid
                        ? 'You'
                        : widget.name,
                  ),
                ),
                IconButton(
                  key: const Key('cancelReply'),
                  tooltip: 'Cancel reply',
                  onPressed: () => ref.read(provider.notifier).clear(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
    );
  }
}
