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
  int _revision = 0;
  bool _sending = false;

  int get revision => _revision;

  void _changed() {
    if (text == _lastText) return;
    _lastText = text;
    _revision++;
    drafts.save(chatId, text, ownerUid: ownerUid);
  }

  void sendingChanged(bool sending) {
    if (_sending == sending) return;
    _sending = sending;
    // A send may finish after leaving the route. Do not restore its attempted
    // text as an unsent draft; edits made during the send are saved separately.
    drafts.save(chatId, sending ? '' : text, ownerUid: ownerUid);
  }

  @override
  void dispose() {
    removeListener(_changed);
    super.dispose();
  }
}
