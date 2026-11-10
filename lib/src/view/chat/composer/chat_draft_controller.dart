import 'package:fireplace/src/model/chat/chat_drafts.dart';
import 'package:flutter/widgets.dart';

class ChatDraftController extends TextEditingController {
  ChatDraftController({
    required this.drafts,
    required this.chatId,
    required this.ownerUid,
  }) : super(text: drafts.textFor(chatId, ownerUid: ownerUid)) {
    _lastText = text;
    selection = TextSelection.collapsed(offset: text.length);
    addListener(_changed);
  }

  final ChatDrafts drafts;
  final String chatId;
  final String? ownerUid;
  late String _lastText;

  // Sending empties the text, which saves an empty draft here: a message
  // that has been handed over is never restored as an unsent draft.
  void _changed() {
    if (text == _lastText) return;
    _lastText = text;
    drafts.save(chatId, text, ownerUid: ownerUid);
  }

  @override
  void dispose() {
    removeListener(_changed);
    super.dispose();
  }
}
