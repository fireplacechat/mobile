// Controlled SDK snapshots for tests that need pending writes. The ordinary
// fake always reports hasPendingWrites=false and cannot model local echoes.
// These SDK interfaces are intentionally implemented by mutable test fakes.
// ignore_for_file: subtype_of_sealed_class, must_be_immutable

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

typedef Json = Map<String, dynamic>;

class PendingFirestore extends Fake implements FirebaseFirestore {
  final collections = <String, PendingCollection>{};
  Future<void> Function(String path)? onDelete;
  Future<void> Function(String path)? onSet;

  @override
  PendingCollection collection(String path) =>
      collections.putIfAbsent(path, () => PendingCollection(this, path));

  Future<void> close() async {
    for (final collection in collections.values) {
      await collection.events.close();
    }
  }
}

// Tests supply exactly the matching documents, so query modifiers need no
// implementation here. Real query filtering/paging is tested with fake Firebase.
class PendingCollection extends Fake implements CollectionReference<Json> {
  PendingCollection(this.db, this.path);
  final PendingFirestore db;
  @override
  final String path;
  final events = StreamController<QuerySnapshot<Json>>.broadcast();
  QuerySnapshot<Json> current = PendingSnapshot(const []);
  bool metadataChanges = false;

  void emit(QuerySnapshot<Json> snapshot) {
    current = snapshot;
    events.add(snapshot);
  }

  @override
  PendingDocument doc([String? path]) =>
      PendingDocument(db, '${this.path}/$path');
  @override
  Future<QuerySnapshot<Json>> get([GetOptions? options]) async => current;
  @override
  Query<Json> orderBy(Object field, {bool descending = false}) => this;
  @override
  Query<Json> limit(int limit) => this;
  @override
  Stream<QuerySnapshot<Json>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) {
    metadataChanges = includeMetadataChanges;
    return Stream.multi((sink) {
      final sub = events.stream.listen(sink.add);
      sink.onCancel = sub.cancel;
      sink.add(current);
    });
  }
}

class PendingDocument extends Fake implements DocumentReference<Json> {
  PendingDocument(this.db, this.path);
  final PendingFirestore db;
  @override
  final String path;
  @override
  CollectionReference<Json> collection(String collectionPath) =>
      db.collection('$path/$collectionPath');
  @override
  Future<void> delete() async => db.onDelete?.call(path);
  @override
  Future<void> set(Json data, [SetOptions? options]) async =>
      db.onSet?.call(path);
}

class PendingMetadata extends Fake implements SnapshotMetadata {
  PendingMetadata(this.hasPendingWrites);
  @override
  final bool hasPendingWrites;
  @override
  bool get isFromCache => hasPendingWrites;
}

class PendingMessage extends Fake implements QueryDocumentSnapshot<Json> {
  PendingMessage(this.id, this.value, {bool pending = false})
    : metadata = PendingMetadata(pending);
  @override
  final String id;
  final Json value;
  @override
  final SnapshotMetadata metadata;
  @override
  Json data() => value;
}

class PendingChange extends Fake implements DocumentChange<Json> {
  PendingChange(this.doc, this.type);
  @override
  final QueryDocumentSnapshot<Json> doc;
  @override
  final DocumentChangeType type;
}

class PendingSnapshot extends Fake implements QuerySnapshot<Json> {
  PendingSnapshot(
    this.docs, {
    this.type = DocumentChangeType.added,
    bool pending = false,
  }) : metadata = PendingMetadata(pending);
  @override
  final SnapshotMetadata metadata;
  @override
  final List<QueryDocumentSnapshot<Json>> docs;
  final DocumentChangeType type;
  @override
  List<DocumentChange<Json>> get docChanges => [
    for (final doc in docs) PendingChange(doc, type),
  ];
}
