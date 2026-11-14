import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/chat_color_preference.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/chat/message_compose_target.dart';
import 'package:fireplace/src/model/chat/message_limits.dart';
import 'package:fireplace/src/model/chat/message_controls.dart';
import 'package:fireplace/src/view/chat/widgets/reply_panel.dart';

class ComposerContextView {
  const ComposerContextView({
    required this.focus,
    this.bar,
    this.editText,
    this.submit,
    this.busy = false,
    this.canSubmit = true,
  });
  final FocusNode focus;
  final Widget? bar;
  final TextEditingController? editText;
  final Future<void> Function()? submit;
  final bool busy, canSubmit;
}

class MessageComposerContext extends ConsumerStatefulWidget {
  const MessageComposerContext({
    super.key,
    required this.chatId,
    required this.name,
    required this.builder,
  });
  final String chatId, name;
  final Widget Function(BuildContext, ComposerContextView) builder;
  @override
  ConsumerState<MessageComposerContext> createState() =>
      _MessageComposerContextState();
}

class _MessageComposerContextState
    extends ConsumerState<MessageComposerContext> {
  final _focus = FocusNode();
  final _edit = TextEditingController();
  @override
  void initState() {
    super.initState();
    _edit.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focus.dispose();
    _edit.removeListener(_changed);
    _edit.dispose();
    super.dispose();
  }

  Future<void> _submitEdit() async {
    final provider = messageComposeProvider(widget.chatId);
    final target = ref.read(provider);
    if (target?.action != MessageComposeAction.edit ||
        _edit.text.trim().isEmpty ||
        _edit.text.trim() == target?.message.body) {
      return;
    }
    final consumed = await ref
        .read(messageControlsProvider(widget.chatId).notifier)
        .edit(target!.message.id, _edit.text);
    if (!mounted) return;
    if (consumed && identical(ref.read(provider), target)) {
      ref.read(provider.notifier).clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = messageComposeProvider(widget.chatId);
    ref.listen(provider, (_, next) {
      if (next?.action == MessageComposeAction.edit) {
        _edit.value = TextEditingValue(
          text: next!.message.body,
          selection: TextSelection.collapsed(offset: next.message.body.length),
        );
      } else {
        _edit.clear();
      }
      if (next != null) _focus.requestFocus();
    });
    final target = ref.watch(provider);
    final colors = ref.watch(chatBubbleColorsProvider);
    final uid = ref.watch(appSessionProvider.select((s) => s.value?.uid));
    final messages = ref.watch(messagesProvider(widget.chatId)).value;
    final live = messages?.where((m) => m.id == target?.message.id).firstOrNull;
    final editing = target?.action == MessageComposeAction.edit;
    final busy = ref.watch(
      messageControlsProvider(widget.chatId).select((s) => s.busy),
    );
    if (editing && (live == null || live.remotelyDeleted)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(ref.read(provider), target)) {
          ref.read(provider.notifier).clear();
        }
      });
    }
    return widget.builder(
      context,
      ComposerContextView(
        focus: _focus,
        editText: editing ? _edit : null,
        submit: editing ? _submitEdit : null,
        busy: editing && busy,
        canSubmit:
            !editing ||
            (_edit.text.trim() != live?.body &&
                live != null &&
                !live.remotelyDeleted),
        bar: target == null
            ? null
            : editing
            ? Row(
                key: const Key('editComposerPreview'),
                children: [
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 18),
                          SizedBox(width: 8),
                          Flexible(child: Text('Edit message')),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('cancelEdit'),
                    tooltip: 'Cancel edit',
                    onPressed: () => ref.read(provider.notifier).clear(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              )
            : ReplyPanel(
                key: const Key('replyComposerPreview'),
                author: target.message.senderUid == uid ? 'You' : widget.name,
                body: clipMessage(live?.body ?? '', 1024),
                unavailable: live == null || live.remotelyDeleted,
                // The colour of the person replied to: theirs, or this
                // account's own when replying to oneself.
                color:
                    (target.message.senderUid == uid
                            ? colors.outgoing
                            : ref.watch(
                                peerColorProvider(target.message.senderUid),
                              ))
                        .accentText(Theme.of(context).brightness),
                onCancel: () => ref.read(provider.notifier).clear(),
              ),
      ),
    );
  }
}
