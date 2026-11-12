import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/model/chat/memory_pending.dart';
import 'package:fireplace/src/view/chat/timeline_messages.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

LocalMessage at(String id, int minute, {bool deleted = false}) => LocalMessage(
  id: id,
  chatId: 'alice_fred',
  senderUid: 'fred',
  senderDevice: 'device',
  outgoing: false,
  sentAt: fixtureTime.add(Duration(minutes: minute)),
  body: deleted ? '' : 'message $id',
  remotelyDeleted: deleted,
);

MemoryPending pending(String id, int minute) => MemoryPending(
  SendNotConfirmedException(
    outcome: SendOutcome.publishUnknown,
    chatId: 'alice_fred',
    messageId: id,
    body: 'pending $id',
    attemptedAt: fixtureTime.add(Duration(minutes: minute)),
    persisted: false,
  ),
);

void main() {
  TimelineMessages run({
    List<LocalMessage> stored = const [],
    List<MemoryPending> memory = const [],
    String? location,
    bool showAll = false,
  }) => timelineMessages(
    chatId: 'alice_fred',
    stored: stored,
    pending: memory,
    session: null,
    location: location,
    showAll: showAll,
    outgoingSends: const [],
  );

  test('saved and unconfirmed messages merge in time order, once each', () {
    final t = run(
      stored: [at('a', 1), at('c', 3)],
      memory: [pending('b', 2), pending('c', 3)], // c is saved already
    );
    expect(t.history.map((m) => m.id), ['a', 'b', 'c']);
    expect(t.shown.map((m) => m.id), ['a', 'b', 'c']);
    expect(t.target, -1);
  });

  test('messages deleted for everyone are left out', () {
    final t = run(stored: [at('a', 1), at('gone', 2, deleted: true)]);
    expect(t.history.map((m) => m.id), ['a']);
  });

  test('a jump shows history up to that message, unless showing all', () {
    final stored = [at('a', 1), at('b', 2), at('c', 3)];
    final jumped = run(stored: stored, location: 'b');
    expect(jumped.target, 1);
    expect(jumped.shown.map((m) => m.id), ['a', 'b']);
    final all = run(stored: stored, location: 'b', showAll: true);
    expect(all.target, -1);
    expect(all.shown.map((m) => m.id), ['a', 'b', 'c']);
  });
}
