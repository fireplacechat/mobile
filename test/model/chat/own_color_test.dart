// One colour per person: it is on the person's profile (decision 0053), read
// with their name, and remembered on the phones of the people they chat with.
import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/model/chat/message_payload.dart';
import 'package:fireplace/src/model/chat/peer_colors.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_service_test.dart' show Dev, addUser;

void main() {
  final now = DateTime.utc(2026, 11, 14);

  test('a message carries no colour, and one from 0.4.0 is read as before', () {
    final plain = encodeMessagePayload(text: 'hi', now: now);
    expect((jsonDecode(utf8.decode(plain)) as Map).containsKey('color'), false);
    for (final sent in ['plum', 'Not A Name', 7]) {
      final read = decodeMessagePayload(
        utf8.encode(
          jsonEncode({'v': 1, 'type': 'text', 'body': 'hi', 'color': sent}),
        ),
      );
      expect(read.body, 'hi', reason: '$sent');
      expect(read.status, MessageStatus.ok, reason: '$sent');
    }
  });

  test('a colour is published on the profile and read with the name', () async {
    final db = FakeFirebaseFirestore();
    await addUser(db, 'alice', 'alice');
    await addUser(db, 'bob', 'bob');
    final alice = await Dev.create(db, 'alice'),
        bob = await Dev.create(db, 'bob');
    addTearDown(() async {
      for (final d in [alice, bob]) {
        await d.close();
        await d.chat.close();
      }
    });
    // Nothing published yet: the name is read, and no colour is known.
    expect(await bob.chat.usernameOf('alice'), 'alice');
    expect(bob.peerColors, {'alice': null});

    await alice.chat.publishColor('plum');
    final profile = (await db.doc('users/alice').get()).data()!;
    expect(profile['color'], 'plum');
    expect(profile['colorAt'], isNotNull);
    expect(profile['username'], 'alice');
    expect(await bob.chat.usernameOf('alice'), 'alice');
    expect(bob.peerColors['alice'], 'plum');

    // Opening the chat soon after does not read the profile again.
    await alice.chat.publishColor('forest');
    await bob.chat.refreshPeerColor('alice');
    expect(bob.peerColors['alice'], 'plum');
    // Someone whose profile was not read yet is read once.
    await bob.chat.publishColor('ocean');
    await alice.chat.refreshPeerColor('bob');
    expect(alice.peerColors['bob'], 'ocean');

    // Reading this account's own profile notes nothing.
    await alice.chat.usernameOf('alice');
    expect(alice.peerColors.containsKey('alice'), false);
    // Something that is not text reads as no colour.
    await db.doc('users/alice').update({'color': 7});
    await bob.chat.usernameOf('alice');
    expect(bob.peerColors['alice'], isNull);
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
    await colors.note('dave', 'ocean');
    await colors.note('dave', null); // taken off the profile: forgotten
    await Future<void>.delayed(Duration.zero);
    expect(colors.of('bob'), 'plum');
    expect(colors.of('alice'), isNull);
    expect(colors.of('carol'), isNull);
    expect(colors.of('dave'), isNull);
    expect(seen, ['bob', 'dave', 'dave']);
    await sub.cancel();

    final again = PeerColors(secrets, 'alice');
    await again.load();
    expect(again.of('bob'), 'plum');
    expect(again.of('dave'), isNull);
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
