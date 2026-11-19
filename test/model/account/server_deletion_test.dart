// Deletion finished by the server (decision 0066): the phone sets the fence,
// erases itself and writes `deletionRequests/{uid}`; the server deletes the
// rest and then the request. When the server does not take it, the app does
// the rest itself, as before.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The sign-in account; records whether the app deleted it itself.
// ignore: must_be_immutable
class SpyUser extends MockUser {
  SpyUser() : super(uid: 'alice', email: 'alice@users.fireplace.invalid');
  int deletions = 0;
  @override
  Future<void> delete() async => deletions++;
}

/// What `finishAccountDeletion` does, in short: mark the request taken,
/// delete the account's records, then the request.
class FakeDeletionServer {
  FakeDeletionServer(this.db, {this.finish = true}) {
    _sub = db.collection('deletionRequests').snapshots().listen((snap) async {
      for (final change in snap.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        requests++;
        await change.doc.reference.update({'startedAt': Timestamp.now()});
        if (!finish) continue;
        final sent = await db
            .collection('chats/alice_bob/messages')
            .where('senderUid', isEqualTo: 'alice')
            .get();
        for (final m in sent.docs) {
          await m.reference.delete();
        }
        await db.doc('usernames/alice').delete();
        await db.doc('users/alice/devices/d1').delete();
        await db.doc('users/alice').delete();
        await change.doc.reference.delete();
      }
    });
  }
  final FakeFirebaseFirestore db;
  final bool finish;
  int requests = 0;
  late final StreamSubscription<void> _sub;
  Future<void> close() => _sub.cancel();
}

/// Lets a test decide how writing the request goes.
class RequestFirestore extends FakeFirebaseFirestore {
  /// A request write that never reaches the server (offline).
  bool offline = false;

  /// A request already there from an earlier attempt: writing it is refused.
  bool earlier = false;

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    final real = super.collection(path);
    return path == 'deletionRequests' && (offline || earlier)
        ? _Requests(real, this)
        : real;
  }
}

// ignore: subtype_of_sealed_class
class _Requests extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  _Requests(this.real, this.db);
  final CollectionReference<Map<String, dynamic>> real;
  final RequestFirestore db;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _Request(real.doc(path), db);
}

// ignore: subtype_of_sealed_class
class _Request extends Fake implements DocumentReference<Map<String, dynamic>> {
  _Request(this.real, this.db);
  final DocumentReference<Map<String, dynamic>> real;
  final RequestFirestore db;
  @override
  String get path => real.path;
  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) {
    if (db.offline) return Completer<void>().future;
    return Future.error(
      FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
    );
  }

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([GetOptions? options]) =>
      real.get(options);
  @override
  Stream<DocumentSnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) => real.snapshots();
}

void main() {
  late RequestFirestore db;
  late SpyUser user;
  late MockFirebaseAuth auth;
  late MemorySecretStore secrets;
  late List<String> steps;

  setUp(() async {
    db = RequestFirestore();
    await db.doc('usernames/alice').set({'uid': 'alice'});
    await db.doc('users/alice').set({'username': 'alice'});
    await db.doc('users/alice/devices/d1').set({'x25519Pub': 'a'});
    await db.doc('chats/alice_bob').set({
      'participants': ['alice', 'bob'],
    });
    await db.doc('chats/alice_bob/messages/a1').set({'senderUid': 'alice'});
    await db.doc('chats/alice_bob/messages/b1').set({'senderUid': 'bob'});
    user = SpyUser();
    auth = MockFirebaseAuth(signedIn: true, mockUser: user);
    secrets = MemorySecretStore()..data['identity:alice'] = 'identity';
    steps = [];
  });

  // The server here answers at once; a long pickup keeps a busy machine from
  // falling back by accident. The fallback tests do not wait that long.
  const answers = Duration(seconds: 5);
  const nobody = Duration(milliseconds: 200);
  AccountService service({
    Duration pickup = answers,
    Duration finish = answers,
  }) => AccountService(
    auth: auth,
    db: db,
    secrets: secrets,
    reauthenticate: (_, _) async {},
    onStep: steps.add,
    serverPickup: pickup,
    serverFinish: finish,
  );

  Future<void> expectAllGone() async {
    expect((await db.doc('users/alice').get()).exists, isFalse);
    expect((await db.doc('usernames/alice').get()).exists, isFalse);
    expect((await db.doc('chats/alice_bob/messages/a1').get()).exists, isFalse);
    expect((await db.doc('chats/alice_bob/messages/b1').get()).exists, isTrue);
    expect(secrets.data, isEmpty);
    expect(auth.currentUser, isNull);
  }

  test('the server finishes it: the phone erases itself, asks, and signs '
      'out', () async {
    final server = FakeDeletionServer(db);
    await service().deleteAccount(password: 'pw');
    expect(steps, AccountService.serverSteps);
    expect(server.requests, 1);
    expect(user.deletions, 0, reason: 'the server deletes the sign-in');
    await expectAllGone();
    expect((await db.doc('deletionRequests/alice').get()).exists, isFalse);
    await server.close();
  });

  test('the phone is erased before the server is asked', () async {
    final server = FakeDeletionServer(db);
    var erasedFirst = false;
    late StreamSubscription<void> watch;
    watch = db.collection('deletionRequests').snapshots().listen((snap) {
      if (snap.docs.isNotEmpty) erasedFirst = secrets.data.isEmpty;
    });
    await service().deleteAccount(password: 'pw');
    expect(erasedFirst, isTrue);
    await watch.cancel();
    await server.close();
  });

  test(
    'nobody takes the request (an older server): the app does the rest',
    () async {
      await service(pickup: nobody).deleteAccount(password: 'pw');
      expect(steps, AccountService.steps);
      expect(user.deletions, 1);
      await expectAllGone();
    },
  );

  test('the server takes it but does not finish in time: the app does the '
      'rest too', () async {
    final server = FakeDeletionServer(db, finish: false);
    await service(finish: nobody).deleteAccount(password: 'pw');
    expect(steps, AccountService.steps);
    await expectAllGone();
    await server.close();
  });

  test('offline, the request never reaches the server: the app does the '
      'rest itself', () async {
    db.offline = true;
    await service(pickup: nobody).deleteAccount(password: 'pw');
    expect(steps, AccountService.steps);
    await expectAllGone();
  });

  test('a request from an earlier attempt is still being worked on: the app '
      'waits for that one', () async {
    await db.doc('deletionRequests/alice').set({'at': Timestamp.now()});
    db.earlier = true;
    final done = service().deleteAccount(password: 'pw');
    // The server, still on the earlier request, finishes now.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    db.earlier = false;
    await db.doc('deletionRequests/alice').update({
      'startedAt': Timestamp.now(),
    });
    await db.doc('chats/alice_bob/messages/a1').delete();
    await db.doc('usernames/alice').delete();
    await db.doc('users/alice').delete();
    await db.doc('deletionRequests/alice').delete();
    await done;
    expect(steps, AccountService.serverSteps);
    await expectAllGone();
  });
}
