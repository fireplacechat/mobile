import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class HarnessUser extends Fake implements User {
  HarnessUser({this.email = 'fred@users.fireplace.invalid'});
  @override
  String get uid => 'fred';
  @override
  final String? email;
}

class HarnessSecrets extends MemorySecretStore {
  final reads = <String>[];
  final deletes = <String>[];
  Future<void> Function(String)? beforeRead;
  Future<void> Function(String)? beforeDelete;
  @override
  Future<String?> read(String key) async {
    reads.add(key);
    await beforeRead?.call(key);
    return super.read(key);
  }

  @override
  Future<void> delete(String key) async {
    deletes.add(key);
    await beforeDelete?.call(key);
    await super.delete(key);
  }

  int get hiddenReads => reads.where((key) => key == 'hidden:fred').length;
}

class HarnessPaths extends PathProviderPlatform {
  HarnessPaths(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

class SessionHarness {
  SessionHarness() {
    PathProviderPlatform.instance = HarnessPaths(dir.path);
  }
  final db = FakeFirebaseFirestore();
  final secrets = HarnessSecrets();
  final dir = Directory.systemTemp.createTempSync('fp-session-provider-');
  final _originalPaths = PathProviderPlatform.instance;
  ProviderContainer? container;
  AppSession? session;
  bool _disposed = false;

  Future<void> profile([Map<String, dynamic>? data]) =>
      db.doc('users/fred').set(data ?? {'username': 'fred'});

  Future<String> chat(
    String peer, {
    bool accepted = true,
    String initiator = 'fred',
  }) async {
    final id = ([peer, 'fred']..sort()).join('_');
    await db.doc('chats/$id').set({
      'participants': ['fred', peer],
      'initiator': initiator,
      'accepted': accepted,
      'requestCount': 0,
      'lastMessageAt': Timestamp.fromDate(DateTime.utc(2026, 10, 7)),
    });
    return id;
  }

  Future<void> hidden(Iterable<String> ids) =>
      secrets.write('hidden:fred', jsonEncode(ids.toList()));

  Future<AppSession?> open({User? user, bool signedOut = false}) async {
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        authUserProvider.overrideWith(
          (_) => Stream.value(signedOut ? null : user ?? HarnessUser()),
        ),
        firestoreProvider.overrideWithValue(db),
        secretStoreProvider.overrideWithValue(secrets),
      ],
    );
    container!.listen(appSessionProvider, (_, _) {}, fireImmediately: true);
    return session = await container!
        .read(appSessionProvider.future)
        .timeout(const Duration(seconds: 15));
  }

  void disposeContainer() {
    if (!_disposed) {
      _disposed = true;
      container?.dispose();
    }
  }

  Future<void> close() async {
    disposeContainer();
    await session?.close();
    PathProviderPlatform.instance = _originalPaths;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}

Future<void> eventually(bool Function() condition) async {
  for (var i = 0; i < 200; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue, reason: 'asynchronous operation did not settle');
}

/// Pause only the preferences sidecar write, without replacing the provider.
class BaselineWriteGate {
  final entered = Completer<void>();
  final release = Completer<void>();
  bool enabled = false;
  bool fail = false;
  void finish() {
    if (!release.isCompleted) release.complete();
  }

  Future<T> run<T>(Future<T> Function() body) => IOOverrides.runZoned(
    body,
    createFile: (path) {
      final file = Zone.root.run(() => File(path));
      return path.endsWith('/chat-ui.enc.tmp') ? _GatedFile(file, this) : file;
    },
  );
}

class _GatedFile extends Fake implements File {
  _GatedFile(this.file, this.gate);
  final File file;
  final BaselineWriteGate gate;
  @override
  String get path => file.path;
  @override
  Future<File> writeAsBytes(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) async {
    if (gate.enabled) {
      if (!gate.entered.isCompleted) gate.entered.complete();
      if (gate.fail) throw const FileSystemException('test sidecar failure');
      await gate.release.future;
    }
    return file.writeAsBytes(bytes, mode: mode, flush: flush);
  }

  @override
  Future<File> rename(String newPath) => file.rename(newPath);
}

Future<void> eventuallyAsync(Future<bool> Function() condition) async {
  for (var i = 0; i < 200; i++) {
    if (await condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(
    await condition(),
    isTrue,
    reason: 'asynchronous operation did not settle',
  );
}
