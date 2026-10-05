import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../crypto/codec.dart';
import 'local_messages.dart';
import 'secret_store.dart';

/// Disk-backed message history, encrypted at rest with AES-256-GCM.
/// The 256-bit key lives in the platform secure store (Keychain/Keystore);
/// the files alone reveal nothing. One file per chat, rewritten atomically on
/// each change, which is fine for personal-scale histories.
class EncryptedFileMessageStore implements LocalMessageStore {
  EncryptedFileMessageStore._(this._dir, this._key);

  final Directory _dir;
  final SecretKey _key;
  static final _aead = AesGcm.with256bits();
  final Map<String, Map<String, LocalMessage>> _cache = {};
  final Map<String, StreamController<List<LocalMessage>>> _ctrls = {};
  Future<void> _writes = Future.value();

  static Future<EncryptedFileMessageStore> open({
    required Directory dir,
    required SecretStore secrets,
    required String uid,
  }) async {
    final keyName = 'msgkey:$uid';
    var raw = await secrets.read(keyName);
    if (raw == null) {
      raw = b64(randomBytes(32));
      await secrets.write(keyName, raw);
    }
    await dir.create(recursive: true);
    return EncryptedFileMessageStore._(dir, SecretKey(unb64(raw)));
  }

  Future<File> _file(String chatId) async {
    final h = (await Sha256().hash(utf8Bytes(chatId))).bytes;
    final name = h.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return File('${_dir.path}/$name.msgs');
  }

  Future<Map<String, LocalMessage>> _load(String chatId) async {
    final cached = _cache[chatId];
    if (cached != null) return cached;
    final map = <String, LocalMessage>{};
    final f = await _file(chatId);
    if (await f.exists()) {
      final bytes = await f.readAsBytes();
      final box = SecretBox.fromConcatenation(
        bytes,
        nonceLength: 12,
        macLength: 16,
      );
      final plain = await _aead.decrypt(
        box,
        secretKey: _key,
        aad: utf8Bytes(chatId),
      );
      for (final j in jsonDecode(utf8.decode(plain)) as List) {
        final m = LocalMessage.fromJson(Map<String, dynamic>.from(j));
        map[m.id] = m;
      }
    }
    return _cache[chatId] = map;
  }

  List<LocalMessage> _sorted(Map<String, LocalMessage> m) =>
      m.values.toList()..sort((a, b) => a.sentAt.compareTo(b.sentAt));

  @override
  Future<bool> has(String chatId, String messageId) async =>
      (await _load(chatId)).containsKey(messageId);

  @override
  Future<void> add(LocalMessage m) {
    final done = _writes.then((_) async {
      // Readers and journal replay must only observe durably committed history.
      final map = {...await _load(m.chatId), m.id: m};
      final box = await _aead.encrypt(
        utf8Bytes(jsonEncode([for (final x in map.values) x.toJson()])),
        secretKey: _key,
        aad: utf8Bytes(m.chatId),
      );
      final f = await _file(m.chatId);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsBytes(
        Uint8List.fromList(box.concatenation()),
        flush: true,
      );
      await tmp.rename(f.path);
      _cache[m.chatId] = map;
      _ctrls[m.chatId]?.add(_sorted(map));
    });
    _writes = done.catchError((_) {});
    return done;
  }

  @override
  Future<LocalMessage?> get(String chatId, String messageId) async =>
      (await _load(chatId))[messageId];

  @override
  Future<void> remove(String chatId, String messageId) {
    final done = _writes.then((_) async {
      final map = {...await _load(chatId)};
      final old = map.remove(messageId);
      if (old == null) return;
      try {
        final box = await _aead.encrypt(
          utf8Bytes(jsonEncode([for (final x in map.values) x.toJson()])),
          secretKey: _key,
          aad: utf8Bytes(chatId),
        );
        final f = await _file(chatId);
        final tmp = File('${f.path}.tmp');
        await tmp.writeAsBytes(
          Uint8List.fromList(box.concatenation()),
          flush: true,
        );
        await tmp.rename(f.path);
      } catch (_) {
        map[messageId] = old; // the disk still has it; keep memory in step
        rethrow;
      }
      _cache[chatId] = map;
      _ctrls[chatId]?.add(_sorted(map));
    });
    _writes = done.catchError((_) {});
    return done;
  }

  @override
  Future<void> deleteChat(String chatId) {
    final done = _writes.then((_) async {
      final f = await _file(chatId);
      if (await f.exists()) await f.delete();
      _cache[chatId] = {};
      _ctrls[chatId]?.add(const []);
    });
    _writes = done.catchError((_) {});
    return done;
  }

  @override
  Stream<List<LocalMessage>> watch(String chatId) {
    final c = _ctrls[chatId] ??= StreamController.broadcast();
    return Stream.multi((s) {
      var cancelled = false;
      final sub = c.stream.listen(s.add, onError: s.addError, onDone: s.close);
      s.onCancel = () async {
        cancelled = true;
        await sub.cancel();
      };
      unawaited(() async {
        try {
          final initial = _sorted(await _load(chatId));
          if (!cancelled) s.add(initial);
        } catch (error, stack) {
          if (!cancelled) s.addError(error, stack);
        }
      }());
    });
  }

  /// Drains pending writes and releases listeners when the session ends.
  Future<void> close() async {
    await _writes;
    for (final controller in _ctrls.values) {
      unawaited(controller.close());
    }
    _ctrls.clear();
  }

  /// Wipes history and key (sign-out / "delete local data").
  Future<void> destroy(SecretStore secrets, String uid) async {
    await secrets.delete('msgkey:$uid');
    if (await _dir.exists()) await _dir.delete(recursive: true);
    _cache.clear();
  }
}
