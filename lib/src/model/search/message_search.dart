import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/model/chat/message_format.dart';

class MessageSearchHit {
  MessageSearchHit(this.message, this.text, this.start, this.end);
  final LocalMessage message;
  final String text;
  final int start, end;
}

/// Case folding for search, per character, so that final sigma and similar
/// match.
String _fold(String s) => s.runes
    .map((r) => String.fromCharCode(r).toLowerCase())
    .join()
    .replaceAll('ς', 'σ');

/// Whether a message's text, as it reads on screen, contains [query], as
/// [searchMessages] decides it. The history database calls the result on its
/// own isolate for each message (decision 0057, step 4), so it captures only
/// the folded query.
bool Function(String body) messageMatcher(String query) {
  final needle = _fold(query.trim());
  return (body) =>
      needle.isNotEmpty && _fold(displayMessage(body).plain).contains(needle);
}

/// Literal, case-insensitive Unicode search. Accents are significant; emoji and
/// combining sequences remain intact. No regex from user input, no disk index.
List<MessageSearchHit> searchMessages(
  Map<String, List<LocalMessage>> history,
  String query, {
  int limit = 100,
}) {
  final needle = _fold(query.trim());
  if (needle.isEmpty) return [];
  if (limit <= 0) return [];
  final results = <MessageSearchHit>[];
  int compare(MessageSearchHit a, MessageSearchHit b) {
    final byTime = b.message.sentAt.compareTo(a.message.sentAt);
    if (byTime != 0) return byTime;
    final byChat = a.message.chatId.compareTo(b.message.chatId);
    return byChat == 0 ? a.message.id.compareTo(b.message.id) : byChat;
  }

  for (final messages in history.values) {
    for (final m in messages) {
      // A line about a group ("alice added bob") is not text anyone wrote.
      if (m.status == MessageStatus.undecryptable ||
          m.status == MessageStatus.notice ||
          m.remotelyDeleted) {
        continue;
      }
      final text = displayMessage(m.body).plain;
      // Lowercasing can change UTF-16 length (e.g. U+0130). Map offsets back.
      final folded = StringBuffer();
      final starts = <int>[], ends = <int>[];
      var offset = 0;
      for (final rune in text.runes) {
        final original = String.fromCharCode(rune),
            lower = original.toLowerCase();
        folded.write(lower == 'ς' ? 'σ' : lower);
        for (var i = 0; i < lower.length; i++) {
          starts.add(offset);
          ends.add(offset + original.length);
        }
        offset += original.length;
      }
      final start = folded.toString().indexOf(needle);
      if (start >= 0) {
        results.add(
          MessageSearchHit(
            m,
            text,
            starts[start],
            ends[start + needle.length - 1],
          ),
        );
        results.sort(compare);
        if (results.length > limit) results.removeLast();
      }
    }
  }
  return results;
}
