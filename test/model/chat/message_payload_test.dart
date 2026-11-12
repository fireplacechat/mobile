import 'dart:convert';

import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/db/message_mutation.dart';
import 'package:fireplace/src/db/message_quote.dart';
import 'package:fireplace/src/model/chat/message_payload.dart';
import 'package:fireplace/src/model/chat/send_mode.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime.fromMillisecondsSinceEpoch(1700000000000);

Map<String, dynamic> json(List<int> bytes) =>
    jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

void main() {
  group('message payload', () {
    test('a text message is version 1 and reads back', () {
      final plain = encodeMessagePayload(text: 'hello', now: now);
      expect(json(plain), {
        'v': 1,
        'type': 'text',
        'body': 'hello',
        'ts': now.millisecondsSinceEpoch,
      });
      final read = decodeMessagePayload(plain);
      expect(read.body, 'hello');
      expect(read.status, MessageStatus.ok);
      expect(read.mutation, isNull);
      expect(read.quote, isNull);
    });

    test('a quoting message is version 3 and keeps its quote', () {
      const quote = MessageQuote(
        targetId: 'm1',
        senderUid: 'bob',
        body: 'the original',
      );
      final plain = encodeMessagePayload(text: 'reply', now: now, quote: quote);
      expect(json(plain)['v'], 3);
      final read = decodeMessagePayload(plain);
      expect(read.body, 'reply');
      expect(read.quote!.toJson(), quote.toJson());
    });

    test('reactions and deletes are version 2, edits version 3', () {
      for (final (mutation, version) in [
        (
          const MessageMutation(
            kind: MessageMutationKind.reaction,
            targetId: 'm1',
            emoji: '👍',
            revision: 1,
            operation: ReactionOperation.set,
          ),
          2,
        ),
        (
          const MessageMutation(
            kind: MessageMutationKind.delete,
            targetId: 'm1',
          ),
          2,
        ),
        (
          const MessageMutation(
            kind: MessageMutationKind.edit,
            targetId: 'm1',
            body: 'fixed',
            revision: 1,
          ),
          3,
        ),
      ]) {
        final plain = encodeMessagePayload(
          text: '',
          now: now,
          mutation: mutation,
        );
        expect(json(plain)['v'], version, reason: mutation.kind.name);
        final read = decodeMessagePayload(plain);
        expect(read.body, isEmpty);
        expect(read.status, MessageStatus.ok);
        expect(read.mutation!.toJson(), mutation.toJson());
      }
    });

    test('an unknown kind from a newer app shows a placeholder', () {
      final read = decodeMessagePayload(
        utf8.encode(jsonEncode({'v': 9, 'type': 'sticker'})),
      );
      expect(read.body, '[unsupported message]');
      expect(read.status, MessageStatus.ok);
    });

    test('an unreadable payload is a malformed message', () {
      for (final bytes in [
        utf8.encode('not json'),
        utf8.encode(
          jsonEncode({'v': 3, 'type': 'text', 'body': 'x', 'quote': 5}),
        ),
        [0xff, 0xfe],
      ]) {
        final read = decodeMessagePayload(bytes);
        expect(read.body, 'Malformed message.');
        expect(read.status, MessageStatus.undecryptable);
        expect(read.quote, isNull);
        expect(read.mutation, isNull);
      }
    });
  });

  group('send mode', () {
    test('an accepted chat, or one older than requests, is normal', () {
      expect(
        SendMode.check({'accepted': true}, uid: 'a', changesMessage: true),
        SendMode.normal,
      );
      expect(
        SendMode.check(const {}, uid: 'a', changesMessage: true),
        SendMode.normal,
      );
      expect(SendMode.normal.chatChange, isNull);
    });

    test('my unanswered chat is a request, limited to three', () {
      final chat = {'accepted': false, 'initiator': 'a', 'requestCount': 2};
      expect(
        SendMode.check(chat, uid: 'a', changesMessage: false),
        SendMode.request,
      );
      expect(SendMode.request.chatChange!.keys, {
        'lastMessageAt',
        'requestCount',
      });
      expect(
        () => SendMode.check(
          {...chat, 'requestCount': ChatService.requestLimit},
          uid: 'a',
          changesMessage: false,
        ),
        throwsA(isA<ChatException>()),
      );
    });

    test('replying to their request accepts it', () {
      final mode = SendMode.check(
        {'accepted': false, 'initiator': 'b'},
        uid: 'a',
        changesMessage: false,
      );
      expect(mode, SendMode.accepting);
      expect(mode.chatChange!['accepted'], isTrue);
    });

    test('reactions, edits, deletes and quotes wait for acceptance', () {
      expect(
        () => SendMode.check(
          {'accepted': false, 'initiator': 'b'},
          uid: 'a',
          changesMessage: true,
        ),
        throwsA(isA<ChatException>()),
      );
    });
  });
}
