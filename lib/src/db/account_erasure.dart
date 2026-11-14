import 'dart:convert';
import 'dart:io';

import 'package:fireplace/src/db/secret_store.dart';
import 'package:fireplace/src/db/shared_lock.dart';

/// Erases only the requested account, including device-id-based sessions and
/// legacy journals. No cryptographic runtime is required to delete stored data.
Future<void> eraseAccountSecrets(SecretStore store, String uid) async {
  final snapshot = await store.readAll();
  final devices = <String>{};
  for (final kind in ['device', 'bundle']) {
    final raw = snapshot['$kind:$uid'];
    if (raw == null) continue;
    try {
      final value = jsonDecode(raw);
      if (value is Map && value['deviceId'] is String) {
        devices.add(value['deviceId'] as String);
      }
    } on FormatException {
      // Prekey names can still identify devices if a JSON record is damaged.
    }
  }
  final prekeys = 'prekeys:$uid:';
  for (final name in snapshot.keys) {
    if (name.startsWith(prekeys)) devices.add(name.substring(prekeys.length));
  }
  devices.removeWhere((id) => id.isEmpty || id.contains(':'));
  const accountKinds = [
    'identity',
    'device',
    'bundle',
    'msgkey',
    'chatprefskey',
    'hidden',
    'pushasked',
    'pushoff',
    'pushnopreview',
    'pushhidename',
    'pushsilent',
    'pushchats',
  ];
  final exact = {for (final kind in accountKinds) '$kind:$uid'};
  exact.addAll([
    'ui:theme-mode:account:$uid',
    'ui:chat-colors:account:$uid',
    'ui:send-sound:account:$uid',
  ]);
  bool owns(String name) {
    if (exact.contains(name) || name.startsWith(prekeys)) return true;
    for (final device in devices) {
      if (name.startsWith('sess:$device:') ||
          name.startsWith('cursor:$device:') ||
          name == 'journal:$device' ||
          name == 'journals:$device' ||
          name.startsWith('journal:$device:')) {
        return true;
      }
    }
    for (final kind in ['pin', 'verified', 'known']) {
      final prefix = '$kind:account:';
      if (!name.startsWith(prefix)) continue;
      try {
        final owners = jsonDecode(name.substring(prefix.length));
        return owners is List && owners.length == 2 && owners.first == uid;
      } on FormatException {
        return false;
      }
    }
    if (name == 'ios-preview-auth') {
      try {
        final data = jsonDecode(snapshot[name]!);
        return data is Map && data['uid'] == uid;
      } on FormatException {
        return false;
      }
    }
    return false;
  }

  final names = snapshot.keys.where(owns).toList();
  // Keep ownership anchors until all derived keys are gone, so a failed
  // keychain delete can be resumed without guessing another account's keys.
  names.remove('device:$uid');
  names.remove('bundle:$uid');
  final prekeyNames = names.where((name) => name.startsWith(prekeys)).toList();
  names.removeWhere((name) => name.startsWith(prekeys));
  for (final name in names) {
    await store.delete(name);
  }
  for (final name in prekeyNames) {
    await store.delete(name);
  }
  await store.delete('bundle:$uid');
  await store.delete('device:$uid');
}

Future<void> eraseAccountHistory({
  required String uid,
  required List<Directory> roots,
  required SharedLock Function(Directory history) lockFor,
}) async {
  if (uid.isEmpty ||
      uid.contains('/') ||
      uid.contains(r'\') ||
      uid.contains('\u0000')) {
    throw StateError('Invalid account storage path.');
  }
  for (final root in roots) {
    final history = Directory('${root.path}/messages_$uid');
    final lock = lockFor(history);
    try {
      await lock.run(() async {
        final type = await FileSystemEntity.type(
          history.path,
          followLinks: false,
        );
        if (type == FileSystemEntityType.notFound) return;
        if (type != FileSystemEntityType.directory) {
          throw StateError('Unexpected account storage link.');
        }
        await history.delete(recursive: true);
      });
    } finally {
      await lock.close();
    }
  }
}
