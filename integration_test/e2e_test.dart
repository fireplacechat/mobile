// NOTE: written but NOT YET RUN - the Android emulator crashes on the original dev machine.
// Runs on an Android emulator against the local Firebase emulators with the
// REAL firestore.rules:
//   firebase emulators:start --only auth,firestore --project fireplace-chat-app
//   flutter test integration_test --dart-define=USE_EMULATOR=true
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:fireplace/firebase_options.dart';
import 'package:fireplace/fireplace_crypto.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Creates an invite the way the operator tool does, but through the Firestore
/// emulator's admin bypass (`Authorization: Bearer owner`). Returns the code.
Future<String> newInvite() async {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  final rnd = Random.secure();
  final code = List.generate(16, (_) => alphabet[rnd.nextInt(32)]).join();
  final id = await AuthService.inviteHash(code);
  final client = HttpClient();
  final req = await client.patchUrl(
    Uri.parse(
      'http://$host:8080/v1/projects/fireplace-chat-app/databases/(default)/documents/invites/$id',
    ),
  );
  req.headers
    ..set('Authorization', 'Bearer owner')
    ..contentType = ContentType.json;
  req.write(
    jsonEncode({
      'fields': {
        'note': {'stringValue': 'e2e'},
      },
    }),
  );
  final res = await req.close();
  client.close();
  if (res.statusCode != 200) {
    throw StateError('could not create invite: ${res.statusCode}');
  }
  return code;
}

const host = String.fromEnvironment('EMULATOR_HOST', defaultValue: '10.0.2.2');

class TestUser {
  TestUser(this.name, this.auth, this.db);
  final String name;
  final FirebaseAuth auth;
  final FirebaseFirestore db;
  late final AuthService authService = AuthService(auth, db);
  final secrets = MemorySecretStore();
  final messages = MemoryMessageStore();
  late final KeyService keys = KeyService(db, secrets);
  late ChatService chat;
  final subs = <StreamSubscription<void>>[];

  Future<void> signUpAndInit() async {
    final user = await authService.signUp(
      username: name,
      password: 'correct horse battery',
      inviteCode: await newInvite(),
    );
    final dev = await keys.ensureDevice(user.uid);
    await PreKeyService(db, secrets).maintain(user.uid, dev);
    chat = ChatService(
      db: db,
      uid: user.uid,
      device: dev,
      keys: keys,
      prekeys: PreKeyService(db, secrets),
      secrets: secrets,
      messages: messages,
    );
  }
}

Future<TestUser> makeUser(String appName, String name) async {
  final app = appName == '[DEFAULT]'
      ? Firebase.app()
      : await Firebase.initializeApp(
          name: appName,
          options: DefaultFirebaseOptions.currentPlatform,
        );
  final auth = FirebaseAuth.instanceFor(app: app);
  final db = FirebaseFirestore.instanceFor(app: app);
  await auth.useAuthEmulator(host, 9099);
  db.useFirestoreEmulator(host, 8080);
  db.settings = const Settings(persistenceEnabled: false);
  return TestUser(name, auth, db);
}

Future<void> eventually(Future<bool> Function() cond, String why) async {
  for (var i = 0; i < 150; i++) {
    if (await cond()) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  fail('timed out: $why');
}

Future<bool> has(TestUser u, String chatId, String body) async =>
    (await u.messages.watch(chatId).first).any((m) => m.body == body);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('two users, real rules: sign up, chat E2EE, attacks denied', (
    t,
  ) async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    final stamp = DateTime.now().millisecondsSinceEpoch % 100000000;
    final alice = await makeUser('[DEFAULT]', 'alice_$stamp');
    final bob = await makeUser('second', 'bob_$stamp');
    final eve = await makeUser('third', 'eve_$stamp');

    await alice.signUpAndInit();
    await bob.signUpAndInit();
    await eve.signUpAndInit();

    // Duplicate username is refused by the rules, and the stray auth account is cleaned up.
    final dupe = await makeUser('fourth', 'x');
    await expectLater(
      dupe.authService.signUp(
        username: alice.name,
        password: 'another password',
        inviteCode: await newInvite(),
      ),
      throwsA(isA<AuthException>()),
    );
    expect(dupe.auth.currentUser, isNull);
    // Signing up without a valid invite is refused by the rules, and rolled back.
    await expectLater(
      dupe.authService.signUp(
        username: 'noinvite_${DateTime.now().millisecondsSinceEpoch % 100000}',
        password: 'another password',
        inviteCode: 'AAAA-BBBB-CCCC-DDDD',
      ),
      throwsA(isA<AuthException>()),
    );
    expect(dupe.auth.currentUser, isNull);

    // Wrong password is a generic failure.
    await bob.auth.signOut();
    await expectLater(
      bob.authService.signIn(username: bob.name, password: 'nope nope nope'),
      throwsA(isA<AuthException>()),
    );
    await bob.authService.signIn(
      username: bob.name,
      password: 'correct horse battery',
    );

    // Chat both ways.
    final chatId = await alice.chat.startChat(bob.name);
    expect(await bob.chat.startChat(alice.name), chatId);
    alice.subs.add(alice.chat.startSync(chatId));
    bob.subs.add(bob.chat.startSync(chatId));
    await alice.chat.sendText(chatId, 'hello from the real emulator');
    await eventually(
      () => has(bob, chatId, 'hello from the real emulator'),
      'bob receives',
    );
    await bob.chat.sendText(chatId, 'and back again');
    await eventually(
      () => has(alice, chatId, 'and back again'),
      'alice receives',
    );

    // Server holds ciphertext only.
    final raw = await alice.db.collection('chats/$chatId/messages').get();
    expect(raw.docs, hasLength(2));
    expect(
      raw.docs.map((d) => d.data().toString()).join().contains('real emulator'),
      isFalse,
    );

    // Rules: outsider cannot read the chat or inject messages.
    await expectLater(
      eve.db.collection('chats/$chatId/messages').get(),
      throwsA(isA<FirebaseException>()),
    );
    await expectLater(
      eve.db.collection('chats/$chatId/messages').add({
        'senderUid': eve.auth.currentUser!.uid,
        'senderDevice': 'x',
        'ts': FieldValue.serverTimestamp(),
        'envelopes': {'a': {}},
      }),
      throwsA(isA<FirebaseException>()),
    );
    // Rules: cannot send plaintext fields or spoof sender.
    await expectLater(
      alice.db.collection('chats/$chatId/messages').add({
        'senderUid': alice.auth.currentUser!.uid,
        'senderDevice': 'x',
        'ts': FieldValue.serverTimestamp(),
        'envelopes': {'a': {}},
        'text': 'plain',
      }),
      throwsA(isA<FirebaseException>()),
    );
    await expectLater(
      alice.db.collection('chats/$chatId/messages').add({
        'senderUid': bob.auth.currentUser!.uid,
        'senderDevice': 'x',
        'ts': FieldValue.serverTimestamp(),
        'envelopes': {'a': {}},
      }),
      throwsA(isA<FirebaseException>()),
    );
    // Rules: nobody can list all users.
    await expectLater(
      eve.db.collection('users').get(),
      throwsA(isA<FirebaseException>()),
    );

    // Identity pinning works against real device documents.
    final pinned = await alice.keys.pinnedIdentity(bob.chat.uid);
    expect(pinned, isNotNull);
    expect(b64(pinned!), b64(bob.chat.device.identity.publicBytes));

    for (final u in [alice, bob, eve]) {
      for (final s in u.subs) {
        await s.cancel();
      }
    }
  });
}
