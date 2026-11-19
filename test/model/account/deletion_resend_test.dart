// A delete that reached the server but lost its reply (issue 119). Firestore
// sends a pending write again when the connection drops before the server
// answers. The second send then deletes a document that is already gone, and
// the rules for messages and usernames read `resource.data`, so they refuse
// it: deletion stopped with "Deletion did not finish" although the delete had
// worked. These tests send every delete twice and refuse the second send.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:flutter_test/flutter_test.dart';

FirebaseException refused() =>
    FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');

/// Sends each delete a second time after it succeeds, as Firestore does when
/// the reply is lost. The real rules refuse the second send, because the
/// document is gone and `resource.data` is null (checked on the Firestore
/// emulator with the deployed rules); the fake's rules cannot read
/// `resource`, so the refusal is made here.
class ResendingFirestore extends FakeFirebaseFirestore {
  bool resend = false;

  /// Refuses every message delete outright, as for a real denial.
  bool refuseMessages = false;

  @override
  WriteBatch batch() => resend ? _ResendingBatch(this) : super.batch();

  WriteBatch plainBatch() => super.batch();

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    final real = super.collection(path);
    return resend && path == 'usernames' ? _Names(real) : real;
  }
}

Future<bool> _gone(DocumentReference ref) async => !(await ref.get()).exists;

class _ResendingBatch extends Fake implements WriteBatch {
  _ResendingBatch(this.db);
  final ResendingFirestore db;
  final _refs = <DocumentReference>[];

  @override
  void delete(DocumentReference document) => _refs.add(document);

  @override
  Future<void> commit() async {
    if (db.refuseMessages && _refs.any((r) => r.path.contains('/messages/'))) {
      throw refused();
    }
    final batch = db.plainBatch();
    for (final ref in _refs) {
      batch.delete(ref);
    }
    await batch.commit();
    // The resend: every document in it is gone now.
    for (final ref in _refs) {
      if (ref.path.contains('/messages/') && await _gone(ref)) throw refused();
    }
  }
}

// ignore: subtype_of_sealed_class
class _Names extends Fake implements CollectionReference<Map<String, dynamic>> {
  _Names(this.real);
  final CollectionReference<Map<String, dynamic>> real;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _Name(real.doc(path));
}

// ignore: subtype_of_sealed_class
class _Name extends Fake implements DocumentReference<Map<String, dynamic>> {
  _Name(this.real);
  final DocumentReference<Map<String, dynamic>> real;

  @override
  String get id => real.id;
  @override
  String get path => real.path;
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([GetOptions? options]) =>
      real.get(options);
  @override
  Future<void> delete() async {
    await real.delete();
    throw refused(); // the resend
  }
}

void main() {
  late ResendingFirestore db;
  late MockFirebaseAuth auth;

  setUp(() async {
    db = ResendingFirestore();
    await db.doc('usernames/alice').set({'uid': 'alice'});
    await db.doc('users/alice').set({'username': 'alice'});
    await db.doc('chats/alice_bob').set({
      'participants': ['alice', 'bob'],
    });
    for (final (id, sender) in [('m1', 'alice'), ('m2', 'alice')]) {
      await db.doc('chats/alice_bob/messages/$id').set({'senderUid': sender});
    }
    auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'alice', email: 'alice@users.fireplace.invalid'),
    );
    db.resend = true;
  });

  AccountService service() => AccountService(
    auth: auth,
    db: db,
    secrets: MemorySecretStore(),
    reauthenticate: (_, _) async {},
  );

  test('deletion finishes when every delete is sent twice', () async {
    await service().deleteAccount(password: 'pw');
    db.resend = false;
    final left = await db.collection('chats/alice_bob/messages').get();
    expect(left.docs, isEmpty);
    expect((await db.doc('usernames/alice').get()).exists, isFalse);
    expect((await db.doc('users/alice').get()).exists, isFalse);
  });

  test('a refusal of a message that is still there still stops it', () async {
    db.refuseMessages = true;
    await expectLater(
      service().deleteAccount(password: 'pw'),
      throwsA(
        isA<FirebaseException>().having(
          (e) => e.code,
          'code',
          'permission-denied',
        ),
      ),
    );
    expect(
      (await db.collection('chats/alice_bob/messages').get()).docs,
      hasLength(2),
    );
  });
}
