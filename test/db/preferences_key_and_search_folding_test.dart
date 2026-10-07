// Review findings C03 (a bad stored key must not lock the account out) and C04 (search folding).
import 'dart:io';

import 'package:fireplace/src/model/settings/local_chat_preferences.dart';
import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/db/secret_store.dart';
import 'package:fireplace/src/model/search/message_search.dart';
import 'package:flutter_test/flutter_test.dart';

LocalMessage msg(String id, String body) => LocalMessage(
  id: id,
  chatId: 'c',
  senderUid: 'x',
  senderDevice: 'd',
  outgoing: false,
  sentAt: DateTime(2026),
  body: body,
);

void main() {
  test('C03: an unreadable stored key marks preferences unavailable instead of throwing', () async {
    final dir = await Directory.systemTemp.createTemp('review-prefs-');
    addTearDown(() => dir.delete(recursive: true));
    final secrets = MemorySecretStore();
    await secrets.write('chatprefskey:alice', '!!!not-base64!!!');
    // LocalChatPreferences.open runs inside appSessionProvider, so a throw here blocks the whole app.
    final prefs = await LocalChatPreferences.open(
      dir: dir,
      secrets: secrets,
      uid: 'alice',
    );
    expect(prefs.available, isFalse);
  });
  test(
    'C04: a lowercase query finds Greek capital text with a final sigma',
    () {
      final h = {
        'c': [msg('1', 'ΟΔΟΣ')],
      };
      expect(searchMessages(h, 'οδος'), hasLength(1));
      expect(searchMessages(h, 'ΟΔΟΣ'), hasLength(1));
    },
  );
}
