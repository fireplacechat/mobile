// One colour per person (decision 0052): a text message carries its sender's
// colour, encrypted with the text, and the other person's phone remembers it.
import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/db/message_mutation.dart';
import 'package:fireplace/src/model/chat/message_payload.dart';
import 'package:fireplace/src/model/chat/peer_colors.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_service_test.dart' show Dev, addUser, eventually;

void main() {
  final now = DateTime.utc(2026, 11, 14);

  test('a text message can carry the sender\'s colour; others cannot', () {
    final plain = encodeMessagePayload(text: 'hi', now: now, color: 'plum');
    expect((jsonDecode(utf8.decode(plain)) as Map)['color'], 'plum');
    expect(decodeMessagePayload(plain).color, 'plum');
    expect(decodeMessagePayload(plain).body, 'hi');
    // Without one, the payload is exactly what it was before.
    final bare = encodeMessagePayload(text: 'hi', now: now);
    expect((jsonDecode(utf8.decode(bare)) as Map).containsKey('color'), false);
    expect(decodeMessagePayload(bare).color, isNull);
    // A reaction says nothing about colour.
    final reaction = encodeMessagePayload(
      text: '',
      now: now,
      color: 'plum',
      mutation: MessageMutation(
        kind: MessageMutationKind.reaction,
        targetId: 'm1',
        emoji: '👍',
        operation: ReactionOperation.set,
        revision: 1,
      ),
    );
    expect(
      (jsonDecode(utf8.decode(reaction)) as Map).containsKey('color'),
      false,
    );
  });

  test(
    'a colour that is not a plain name is dropped, and the text is kept',
    () {
      for (final bad in [
        'Plum',
        'plum;drop',
        '',
        'x' * 25,
        '#ff0000',
        7,
        ['plum'],
      ]) {
        final plain = utf8.encode(
          jsonEncode({'v': 1, 'type': 'text', 'body': 'hi', 'color': bad}),
        );
        final read = decodeMessagePayload(plain);
        expect(read.color, isNull, reason: '$bad');
        expect(read.body, 'hi', reason: '$bad');
        expect(read.status, MessageStatus.ok, reason: '$bad');
      }
    },
  );

  test('the other person\'s phone learns the colour from a message, and the '
      'server never sees it', () async {
    final db = FakeFirebaseFirestore();
    await addUser(db, 'alice', 'alice');
    await addUser(db, 'bob', 'bob');
    final alice = await Dev.create(db, 'alice'),
        bob = await Dev.create(db, 'bob');
    final linked = await Dev.linked(db, alice);
    addTearDown(() async {
      for (final d in [alice, bob, linked]) {
        await d.close();
        await d.chat.close();
      }
    });
    const chat = 'alice_bob';
    await db.collection('chats').doc(chat).set({
      'members': ['alice', 'bob'],
      'accepted': true,
    });
    for (final d in [alice, bob, linked]) {
      d.sync(chat);
    }
    alice.color = 'plum';
    await alice.chat.sendText(chat, 'Hello Bob');
    await eventually(() async => (await bob.history(chat)).length == 1);
    await eventually(() async => bob.peerColors['alice'] == 'plum');
    // Alice's other phone gets the copy but notes nothing: it is her colour.
    await eventually(() async => (await linked.history(chat)).length == 1);
    expect(linked.peerColors, isEmpty);
    expect(db.dump(), isNot(contains('plum')));

    // Bob has chosen nothing to send: Alice learns nothing about him.
    await bob.chat.sendText(chat, 'Hello Alice');
    await eventually(() async => (await alice.history(chat)).length == 2);
    expect(alice.peerColors, isEmpty);

    // A change travels with the next message.
    alice.color = 'forest';
    await alice.chat.sendText(chat, 'New colour');
    await eventually(() async => bob.peerColors['alice'] == 'forest');
  });

  test('colours are remembered on the device, per account', () async {
    final secrets = MemorySecretStore();
    final colors = PeerColors(secrets, 'alice');
    await colors.load();
    final seen = <String>[];
    final sub = colors.changes.listen(seen.add);
    await colors.note('bob', 'plum');
    await colors.note('bob', 'plum'); // unchanged: nothing to announce
    await colors.note('alice', 'ember'); // her own: ignored
    await colors.note('carol', 'Not A Name');
    await Future<void>.delayed(Duration.zero);
    expect(colors.of('bob'), 'plum');
    expect(colors.of('alice'), isNull);
    expect(colors.of('carol'), isNull);
    expect(seen, ['bob']);
    await sub.cancel();

    final again = PeerColors(secrets, 'alice');
    await again.load();
    expect(again.of('bob'), 'plum');
    // Another account on this phone has its own.
    final other = PeerColors(secrets, 'dana');
    await other.load();
    expect(other.of('bob'), isNull);
    // A damaged record reads as empty.
    await secrets.write(PeerColors.keyName('alice'), '{not json');
    final damaged = PeerColors(secrets, 'alice');
    await damaged.load();
    expect(damaged.of('bob'), isNull);
  });
}
