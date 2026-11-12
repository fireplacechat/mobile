import 'package:flutter_test/flutter_test.dart';

import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/db/secret_store.dart';
import 'package:fireplace/src/model/notifications/arrival_notifier.dart';
import 'package:fireplace/src/model/notifications/notification_preview.dart';
import 'package:fireplace/src/model/notifications/preview_notifier.dart';

import '../../support/fake_notification_poster.dart';

LocalMessage _m(String id, String body) => LocalMessage(
  id: id,
  chatId: 'alice_bob',
  senderUid: 'bob',
  senderDevice: 'bob-device',
  outgoing: false,
  sentAt: DateTime.utc(2026, 11, 12),
  body: body,
);

void main() {
  late FakePoster poster;
  late MemorySecretStore prefs;
  var onScreen = false;
  late String key;

  setUp(() async {
    poster = FakePoster();
    prefs = MemorySecretStore();
    onScreen = false;
    key = await conversationKey('alice_bob');
  });

  Future<void> deliver(List<LocalMessage> messages) async {
    final notifier = ArrivalNotifier(
      arrivals: Stream.fromIterable(messages),
      uid: 'alice',
      prefs: prefs,
      store: MemoryMessageStore(),
      notifier: PreviewNotifier(poster),
      onScreen: () => onScreen,
      usernameOf: (_) async => 'bob',
    );
    await pumpEventQueue();
    await notifier.close();
  }

  test('off screen, the app posts what it received', () async {
    await deliver([_m('m1', 'Hello')]);
    expect(poster.shown[key], (
      title: 'bob',
      body: 'Hello',
      channel: 'messages',
    ));
  });

  test('on screen, the in-app notice shows it instead', () async {
    onScreen = true;
    await deliver([_m('m1', 'Hello')]);
    expect(poster.log, isEmpty);
  });

  test('names hidden and sound off follow the device choices', () async {
    await prefs.write('pushhidename:alice', '1');
    await prefs.write('pushsilent:alice', '1');
    await deliver([_m('m1', 'Hello')]);
    expect(poster.shown[key], (
      title: 'Fireplace',
      body: 'Hello',
      channel: 'messages_silent',
    ));
  });

  test(
    'previews off or notifications off: the push alerts, not the app',
    () async {
      await prefs.write('pushnopreview:alice', '1');
      await deliver([_m('m1', 'Hello')]);
      await prefs.delete('pushnopreview:alice');
      await prefs.write('pushoff:alice', '1');
      await deliver([_m('m2', 'Again')]);
      expect(poster.log, isEmpty);
    },
  );

  test('messages are posted in the order they arrived', () async {
    await deliver([_m('m1', 'one'), _m('m2', 'two')]);
    expect(poster.log, ['show $key one', 'show $key two']);
  });
}
