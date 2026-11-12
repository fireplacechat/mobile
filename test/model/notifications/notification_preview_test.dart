import 'package:flutter_test/flutter_test.dart';

import 'package:fireplace/src/db/local_messages.dart';
import 'package:fireplace/src/db/message_mutation.dart';
import 'package:fireplace/src/model/notifications/notification_preview.dart';

const _chat = 'alice_bob';
const _key = 'b9ae8cd4f6a7390fb723bb7da8f81908';

LocalMessage _msg(
  String id, {
  String from = 'bob',
  String body = 'Hello there',
  MessageStatus status = MessageStatus.ok,
  MessageMutation? mutation,
  bool remotelyDeleted = false,
}) => LocalMessage(
  id: id,
  chatId: _chat,
  senderUid: from,
  senderDevice: '$from-device',
  outgoing: from == 'alice',
  sentAt: DateTime.utc(2026, 11, 12, 9),
  body: body,
  status: status,
  mutation: mutation,
  remotelyDeleted: remotelyDeleted,
);

List<NotificationChange> _changes(
  LocalMessage arrived, {
  LocalMessage? target,
  bool showPreview = true,
  String title = 'bob',
  Map<String, String> showing = const {},
}) => notificationChanges(
  arrived: arrived,
  target: target,
  ownUid: 'alice',
  conversationKey: _key,
  title: title,
  showPreview: showPreview,
  showing: showing,
);

MessageMutation _react(String target, String emoji, {bool clear = false}) =>
    MessageMutation(
      kind: MessageMutationKind.reaction,
      targetId: target,
      emoji: emoji,
      operation: clear ? ReactionOperation.clear : ReactionOperation.set,
      revision: 1,
    );

void main() {
  test('the conversation key matches the server', () async {
    // Backend `conversationKey('alice_bob')` in functions/lib/push-core.js.
    expect(await conversationKey(_chat), _key);
    expect(await conversationKey('alice_carol'), isNot(_key));
    expect(reactionTag(_key), '$_key.r');
  });

  test('the title is the username, or Fireplace when names are hidden', () {
    expect(notificationTitle(username: 'bob', showName: true), 'bob');
    expect(notificationTitle(username: 'bob', showName: false), 'Fireplace');
    expect(notificationTitle(username: '', showName: true), 'Fireplace');
  });

  test('a message shows the sender and the text', () {
    expect(_changes(_msg('m1')), [
      const ShowNotification(
        tag: _key,
        title: 'bob',
        body: 'Hello there',
        messageId: 'm1',
      ),
    ]);
    expect(
      _changes(_msg('m1'), title: 'Fireplace').single,
      isA<ShowNotification>().having((c) => c.title, 'title', 'Fireplace'),
    );
  });

  test('with previews off every arrival is the plain alert, as before', () {
    final plain = [
      const ShowNotification(
        tag: _key,
        title: 'bob',
        body: 'New Message',
        messageId: 'm1',
      ),
    ];
    expect(_changes(_msg('m1'), showPreview: false), plain);
    expect(
      _changes(
        _msg('m1', mutation: _react('t', '❤️')),
        target: _msg('t', from: 'alice'),
        showPreview: false,
      ),
      plain,
    );
  });

  test('a message that could not be decrypted is the plain alert', () {
    final change =
        _changes(_msg('m1', status: MessageStatus.undecryptable)).single
            as ShowNotification;
    expect(change.body, plainNotificationBody);
    expect(plainNotificationBody, 'New Message');
  });

  test('my own messages from another device never alert', () {
    expect(_changes(_msg('m1', from: 'alice')), isEmpty);
  });

  test('long text is cut to a bounded body; blank text is plain', () {
    final long = 'a' * 5000;
    final body = notificationBody(long);
    expect(body.runes.length, maxNotificationBodyCharacters + 1);
    expect(body.endsWith('…'), isTrue);
    expect(notificationBody('  hi  '), 'hi');
    expect(notificationBody('   '), 'New Message');
    // Characters, not UTF-16 units: an emoji is never split.
    final emoji = '😀' * 2000;
    expect(
      notificationBody(emoji).runes.take(maxNotificationBodyCharacters).toSet(),
      {'😀'.runes.single},
    );
  });

  test('a reaction to my message has its own alert and quotes the start', () {
    final target = _msg(
      't',
      from: 'alice',
      body: 'See you at the station\nat 9, by the clock tower near platform 4',
    );
    final change =
        _changes(_msg('r1', mutation: _react('t', '❤️')), target: target).single
            as ShowNotification;
    expect(change.tag, reactionTag(_key));
    expect(change.messageId, 't');
    expect(change.body, 'Reacted ❤️ to “See you at the station at 9, by the…”');
    expect(reactionNotificationBody('👍', 'Short'), 'Reacted 👍 to “Short”');
    expect(reactionNotificationBody('👍', '   '), 'Reacted 👍');
  });

  test('reactions to their own messages, or to unknown ones, do not alert', () {
    expect(
      _changes(
        _msg('r1', mutation: _react('t', '❤️')),
        target: _msg('t', from: 'bob'),
      ),
      isEmpty,
    );
    expect(_changes(_msg('r1', mutation: _react('t', '❤️'))), isEmpty);
    expect(
      _changes(
        _msg('r1', mutation: _react('t', '❤️')),
        target: _msg('t', from: 'alice', remotelyDeleted: true),
      ),
      isEmpty,
    );
  });

  test('a reaction taken back removes its alert only if it shows', () {
    final undo = _msg('r2', mutation: _react('t', '', clear: true));
    final target = _msg('t', from: 'alice');
    expect(_changes(undo, target: target, showing: {reactionTag(_key): 't'}), [
      RemoveNotification(reactionTag(_key)),
    ]);
    expect(
      _changes(undo, target: target, showing: {reactionTag(_key): 'other'}),
      isEmpty,
    );
  });

  test('an edit never alerts; it updates a showing alert silently', () {
    final edit = _msg(
      'e1',
      mutation: const MessageMutation(
        kind: MessageMutationKind.edit,
        targetId: 'm1',
        body: 'Hello there, fixed',
        revision: 1,
      ),
    );
    final target = _msg('m1');
    expect(_changes(edit, target: target), isEmpty);
    expect(_changes(edit, target: target, showing: {_key: 'm0'}), isEmpty);
    expect(_changes(edit, target: target, showing: {_key: 'm1'}), [
      const ShowNotification(
        tag: _key,
        title: 'bob',
        body: 'Hello there, fixed',
        messageId: 'm1',
        silent: true,
      ),
    ]);
  });

  test('a delete removes the alerts showing that message', () {
    final delete = _msg(
      'd1',
      mutation: const MessageMutation(
        kind: MessageMutationKind.delete,
        targetId: 'm1',
      ),
    );
    expect(_changes(delete, showing: {_key: 'm1'}), [
      const RemoveNotification(_key),
    ]);
    expect(_changes(delete, showing: {reactionTag(_key): 'm1', _key: 'm1'}), [
      const RemoveNotification(_key),
      RemoveNotification(reactionTag(_key)),
    ]);
    expect(_changes(delete, showing: {_key: 'm2'}), isEmpty);
    expect(_changes(delete), isEmpty);
  });
}
