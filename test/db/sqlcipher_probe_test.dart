// The database library the app ships is SQLCipher: a file opened with a key
// is unreadable without it, and holds no plaintext.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('fp_sqlcipher'));
  tearDown(() => dir.deleteSync(recursive: true));

  String hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  test('this build is SQLCipher', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    final version = db.select('PRAGMA cipher_version');
    expect(version, isNotEmpty, reason: 'plain SQLite has no cipher_version');
    expect(version.first.values.first, isA<String>());
  });

  test('a keyed file round-trips, holds no plaintext, and needs its key', () {
    final path = '${dir.path}/probe.db';
    final key = List<int>.generate(32, (i) => i * 7 % 256);
    final db = sqlite3.open(path);
    db.execute('PRAGMA key = "x\'${hex(key)}\'"');
    db.execute('CREATE TABLE m (id TEXT PRIMARY KEY, body TEXT NOT NULL)');
    db.execute('INSERT INTO m VALUES (?, ?)', ['1', 'private fictional text']);
    db.close();

    final raw = String.fromCharCodes(File(path).readAsBytesSync());
    expect(raw, isNot(contains('private fictional text')));
    expect(raw, isNot(contains('SQLite format 3')));

    final again = sqlite3.open(path);
    again.execute('PRAGMA key = "x\'${hex(key)}\'"');
    expect(again.select('SELECT body FROM m').single['body'], contains('fict'));
    again.close();

    final wrong = sqlite3.open(path);
    addTearDown(wrong.close);
    wrong.execute('PRAGMA key = "x\'${hex(List.filled(32, 9))}\'"');
    expect(() => wrong.select('SELECT count(*) FROM m'), throwsA(anything));
    final none = sqlite3.open(path);
    addTearDown(none.close);
    expect(() => none.select('SELECT count(*) FROM m'), throwsA(anything));
  });

  // The database store relies on secure_delete to overwrite what a deletion
  // frees. Shown here on an unencrypted file, where the bytes can be read.
  for (final secure in [true, false]) {
    test('deleted rows are ${secure ? 'overwritten' : 'left behind'} with '
        'secure_delete ${secure ? 'on' : 'off'}', () {
      final path = '${dir.path}/plain-$secure.db';
      final db = sqlite3.open(path);
      db.execute('PRAGMA secure_delete = ${secure ? 'ON' : 'OFF'}');
      db.execute('PRAGMA journal_mode = WAL');
      db.execute('CREATE TABLE m (id INTEGER PRIMARY KEY, body TEXT)');
      for (var i = 0; i < 200; i++) {
        db.execute('INSERT INTO m (body) VALUES (?)', ['fictional secret $i']);
      }
      db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      db.execute('DELETE FROM m WHERE id > 5');
      db.execute('UPDATE m SET body = ?', ['x']);
      db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      db.close();
      final raw = String.fromCharCodes(File(path).readAsBytesSync());
      expect(raw.contains('fictional secret'), !secure);
    });
  }
}
