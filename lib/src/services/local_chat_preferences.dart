// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../crypto/codec.dart';
import 'secret_store.dart';

/// Device-only read bookkeeping and mute/preview preferences. No message bodies.
/// Production writes are authenticated/encrypted, serialized and atomic.
class LocalChatPreferences {
  LocalChatPreferences({
    Future<void> Function(String)? save,
    bool baselineExisting = false,
  }) : _save = save,
       _baselineExisting = baselineExisting;
  final Future<void> Function(String)? _save;
  final seen = <String, Set<String>>{};
  final muted = <String>{};
  bool previewText = true;
  bool _baselineExisting;
  final _baselinedChats = <String>{};
  bool needsBaseline(String chatId) =>
      _baselineExisting && !_baselinedChats.contains(chatId);
  bool _available = true;
  bool get available => _available;
  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;
  Future<void> _writes = Future.value();
  bool _closing = false;

  static Future<LocalChatPreferences> open({
    required Directory dir,
    required SecretStore secrets,
    required String uid,
  }) async {
    final name = 'chatprefskey:$uid';
    var raw = await secrets.read(name);
    if (raw == null) {
      raw = b64(randomBytes(32));
      await secrets.write(name, raw);
    }
    SecretKey? key;
    try {
      final bytes = unb64(raw);
      if (bytes.length == 32) key = SecretKey(bytes);
    } catch (_) {
      // A damaged sidecar key does not lock the owner out of their messages.
    }
    final cipher = AesGcm.with256bits();
    final aad = utf8Bytes('chat-ui-v1:$uid');
    await dir.create(recursive: true);
    final file = File('${dir.path}/chat-ui.enc');
    final exists = await file.exists();
    final prefs = LocalChatPreferences(
      baselineExisting: !exists,
      save: (json) async {
        // A missing/invalid key is repaired only through the confirmed reset.
        final writeKey = key ?? SecretKey(randomBytes(32));
        if (key == null) {
          await secrets.write(name, b64(await writeKey.extractBytes()));
        }
        final box = await cipher.encrypt(
          utf8Bytes(json),
          secretKey: writeKey,
          aad: aad,
        );
        final tmp = File('${file.path}.tmp');
        await tmp.writeAsBytes(
          Uint8List.fromList(box.concatenation()),
          flush: true,
        );
        await tmp.rename(file.path);
        key = writeKey;
      },
    );
    if (key == null) {
      prefs._available = false;
      prefs.previewText = false;
    } else if (exists) {
      try {
        final box = SecretBox.fromConcatenation(
          await file.readAsBytes(),
          nonceLength: 12,
          macLength: 16,
        );
        final data = jsonDecode(
          utf8.decode(await cipher.decrypt(box, secretKey: key!, aad: aad)),
        ) as Map<String, dynamic>;
        for (final e in (data['seen'] as Map<String, dynamic>).entries) {
          prefs.seen[e.key] = (e.value as List).cast<String>().toSet();
        }
        prefs.muted.addAll((data['muted'] as List).cast<String>());
        prefs.previewText = data['previewText'] != false;
        prefs._baselineExisting = data['baselineExisting'] == true;
        prefs._baselinedChats.addAll(
          ((data['baselinedChats'] as List?) ?? []).cast<String>(),
        );
      } catch (_) {
        // A broken UI sidecar must not lock the owner out of their messages,
        // or silently forget an unknown mute setting and reveal previews.
        prefs.seen.clear();
        prefs.muted.clear();
        prefs.previewText = false;
        prefs._available = false;
      }
    }
    return prefs;
  }

  Future<void> _update(void Function() change, {bool recover = false}) {
    if (_closing) {
      return Future.error(StateError('Local preferences are closed'));
    }
    final done = _writes.then((_) async {
      if (!_available && !recover) {
        throw StateError('Local preferences need reset');
      }
      final oldSeen = {
        for (final e in seen.entries) e.key: Set<String>.of(e.value),
      };
      final oldMuted = Set<String>.of(muted);
      final oldPreview = previewText;
      final oldBaseline = _baselineExisting;
      final oldChats = Set<String>.of(_baselinedChats);
      change();
      final nextSeen = {
        for (final e in seen.entries) e.key: Set<String>.of(e.value),
      };
      final nextMuted = Set<String>.of(muted);
      final nextPreview = previewText;
      final nextBaseline = _baselineExisting;
      final nextChats = Set<String>.of(_baselinedChats);
      String encode(
        Map<String, Set<String>> read,
        Set<String> mute,
        bool preview,
        bool baseline,
        Set<String> chats,
      ) => jsonEncode({
        'seen': {for (final e in read.entries) e.key: e.value.toList()},
        'muted': mute.toList(),
        'previewText': preview,
        'baselineExisting': baseline,
        'baselinedChats': chats.toList(),
      });
      final json = encode(
        nextSeen,
        nextMuted,
        nextPreview,
        nextBaseline,
        nextChats,
      );
      seen
        ..clear()
        ..addAll(oldSeen);
      muted
        ..clear()
        ..addAll(oldMuted);
      previewText = oldPreview;
      _baselineExisting = oldBaseline;
      _baselinedChats
        ..clear()
        ..addAll(oldChats);
      if (!recover &&
          json ==
              encode(oldSeen, oldMuted, oldPreview, oldBaseline, oldChats)) {
        return;
      }
      await _save?.call(json);
      seen
        ..clear()
        ..addAll(nextSeen);
      muted
        ..clear()
        ..addAll(nextMuted);
      previewText = nextPreview;
      _baselineExisting = nextBaseline;
      _baselinedChats
        ..clear()
        ..addAll(nextChats);
      _available = true;
      if (!_changes.isClosed) _changes.add(null);
    });
    _writes = done.catchError((_) {});
    return done;
  }

  Future<void> markSeen(String chatId, Iterable<String> ids) {
    final copy = ids.toSet();
    if (copy.difference(seen[chatId] ?? {}).isEmpty) return Future.value();
    return _update(() => (seen[chatId] ??= {}).addAll(copy));
  }

  Future<void> mute(String chatId, bool value) => _update(() {
    if (value) {
      muted.add(chatId);
    } else {
      muted.remove(chatId);
    }
  });
  Future<void> previews(bool value) => _update(() => previewText = value);
  Future<void> seedExisting(String chatId, Iterable<String> ids) async {
    if (!available || !needsBaseline(chatId)) return;
    final snapshot = ids.toSet();
    try {
      await _update(() {
        // A concurrent initial snapshot must not absorb later arrivals.
        if (!needsBaseline(chatId)) return;
        (seen[chatId] ??= {}).addAll(snapshot);
        _baselinedChats.add(chatId);
      });
    } catch (_) {
      _available = false;
      if (!_changes.isClosed) _changes.add(null);
      rethrow;
    }
  }

  Future<void> reset({Map<String, Set<String>> history = const {}}) {
    final snapshot = {
      for (final e in history.entries) e.key: Set<String>.of(e.value),
    };
    return _update(() {
      seen
        ..clear()
        ..addAll(snapshot);
      muted.clear();
      previewText = true;
      _baselineExisting = true;
      _baselinedChats
        ..clear()
        ..addAll(snapshot.keys);
    }, recover: true);
  }

  Future<void> close() async {
    _closing = true;
    await _writes;
    // Do not wait for UI listeners, which may be paused while a route is
    // being disposed. All disk writes have already drained above.
    unawaited(_changes.close());
  }
}
