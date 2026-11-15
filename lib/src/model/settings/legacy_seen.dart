import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/model/settings/local_chat_preferences.dart';

/// Versions before the history database kept a list of every seen message
/// id in the preferences file. Read state is a flag on each message now
/// (issue 180). This carries the list over, once, and then drops it from the
/// file.
///
/// Marking is idempotent and the list is dropped only after every chat is
/// done, so being stopped half-way just means doing it again.
Future<void> moveLegacySeen(
  LocalChatPreferences preferences,
  LocalMessageStore store,
) async {
  if (!preferences.available || preferences.seen.isEmpty) return;
  for (final entry in preferences.seen.entries.toList()) {
    await store.markRead(entry.key, entry.value.toList());
  }
  await preferences.clearLegacySeen();
}
