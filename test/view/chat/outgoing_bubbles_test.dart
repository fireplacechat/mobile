import 'package:fireplace/src/model/chat/outgoing_sends.dart';
import 'package:fireplace/src/view/chat/outgoing_messages.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ui_fixture.dart';

OutgoingSend sending(
  String id,
  String body, {
  DateTime? at,
  Set<String> historyIds = const {},
  bool historyKnown = true,
  OutgoingState state = OutgoingState.sending,
}) => OutgoingSend(
  id: id,
  chatId: 'alice_fred',
  body: body,
  createdAt: at ?? fixtureTime,
  historyKnown: historyKnown,
  historyIds: historyIds,
  state: state,
);

void main() {
  test('a saved send is not drawn again as an optimistic row', () {
    final bubbles = outgoingBubbles(
      [
        sending('outgoing-0', 'hello', historyIds: const {'1'}),
      ],
      [
        message(id: '1', body: 'earlier', outgoing: true),
        message(id: 'saved', body: 'hello', outgoing: true),
      ],
      null,
    );
    expect(bubbles, isEmpty);
  });

  test('an older copy of the same text does not hide a new send', () {
    final bubbles = outgoingBubbles(
      [
        sending('outgoing-0', 'ok', historyIds: const {'old'}),
      ],
      [message(id: 'old', body: 'ok', outgoing: true)],
      null,
    );
    expect(bubbles.map((m) => m.id), ['outgoing-0']);
  });

  test('a second identical send stays while only the first is saved', () {
    final bubbles = outgoingBubbles(
      [
        sending('outgoing-0', 'ok', historyIds: const {'1'}),
        sending(
          'outgoing-1',
          'ok',
          at: fixtureTime.add(const Duration(seconds: 1)),
          historyIds: const {'1'},
        ),
      ],
      [
        message(id: '1', body: 'earlier', outgoing: true),
        message(id: 'saved', body: 'ok', outgoing: true),
      ],
      null,
    );
    expect(bubbles.map((m) => m.id), ['outgoing-1']);
  });

  test('a failed send stays even when history has the same text', () {
    final bubbles = outgoingBubbles(
      [
        sending(
          'outgoing-0',
          'hello',
          historyIds: const {'1'},
          state: OutgoingState.failed,
        ),
      ],
      [
        message(id: '1', body: 'earlier', outgoing: true),
        message(id: 'saved', body: 'hello', outgoing: true),
      ],
      null,
    );
    expect(bubbles.map((m) => m.id), ['outgoing-0']);
  });

  test('a send stays when the history snapshot was not loaded', () {
    final bubbles = outgoingBubbles(
      [sending('outgoing-0', 'hello', historyKnown: false)],
      [message(id: 'saved', body: 'hello', outgoing: true)],
      null,
    );
    expect(bubbles.map((m) => m.id), ['outgoing-0']);
  });
}
