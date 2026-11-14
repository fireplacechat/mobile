// Phones for group tests: each a real GroupService (Rust MLS core) over a
// shared fake Firestore.
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/model/groups/group_models.dart';
import 'package:fireplace/src/model/groups/group_service.dart';
import 'package:flutter_test/flutter_test.dart';

class Phone {
  Phone._(this.uid, this.service, this.messages, this.secrets);
  final String uid;
  final GroupService service;
  final MemoryMessageStore messages;
  final MemorySecretStore secrets;

  static Future<Phone> create(
    FakeFirebaseFirestore db,
    String uid,
    Directory root,
  ) async {
    await db.collection('usernames').doc(uid).set({'uid': uid});
    await db.collection('users').doc(uid).set({
      'username': uid,
      'displayName': uid,
    });
    final secrets = MemorySecretStore();
    final device = await KeyService(db, secrets).ensureDevice(uid);
    final messages = MemoryMessageStore();
    final service = GroupService(
      db: db,
      uid: uid,
      device: device,
      secrets: secrets,
      historyDir: Directory('${root.path}/$uid')..createSync(recursive: true),
      messages: messages,
      requestTimeout: const Duration(seconds: 10),
    );
    await service.start();
    return Phone._(uid, service, messages, secrets);
  }
}

/// Waits (in real time) until [ready] holds.
Future<void> until(
  Future<bool> Function() ready, {
  String what = 'condition',
}) async {
  final end = DateTime.now().add(const Duration(seconds: 20));
  while (!await ready()) {
    if (DateTime.now().isAfter(end)) fail('Timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

Future<List<String>> texts(Phone p, String gid) async => [
  for (final m in await p.messages.watch(groupChatId(gid)).first) m.body,
];
