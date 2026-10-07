import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:fireplace/src/crypto/codec.dart';
import 'package:fireplace/src/model/settings/local_chat_preferences.dart';
import 'package:fireplace/src/db/secret_store.dart';
import 'package:fireplace/src/model/notifications/chat_activity.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/ui_fixture.dart';

Future<void> drain() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  for (final raw in [
    '!!!bad!!!',
    b64(List.filled(31, 1)),
    b64(List.filled(33, 1)),
  ]) {
    test(
      'invalid sidecar key is non-fatal and reset creates a random durable key ($raw)',
      () async {
        final dir = await Directory.systemTemp.createTemp('key-repair-');
        addTearDown(() => dir.delete(recursive: true));
        final secrets = MemorySecretStore();
        await secrets.write('chatprefskey:alice', raw);
        final history = File('${dir.path}/untouched.msgs');
        await history.writeAsString('fixture history preserved');
        final prefs = await LocalChatPreferences.open(
          dir: dir,
          secrets: secrets,
          uid: 'alice',
        );
        expect(prefs.available, isFalse);
        expect(await secrets.read('chatprefskey:alice'), raw);
        await expectLater(prefs.previews(true), throwsStateError);
        await prefs.reset(
          history: {
            'c': {'existing'},
          },
        );
        final repaired = unb64((await secrets.read('chatprefskey:alice'))!);
        expect(repaired, hasLength(32));
        expect(repaired, isNot(everyElement(0)));
        expect(prefs.previewText, isTrue);
        expect(prefs.seen['c'], {'existing'});
        expect(await history.readAsString(), 'fixture history preserved');
        await prefs.close();
        final reopened = await LocalChatPreferences.open(
          dir: dir,
          secrets: secrets,
          uid: 'alice',
        );
        expect(reopened.available, isTrue);
        expect(reopened.needsBaseline('c'), isFalse);
        expect(reopened.seen['c'], {'existing'});
        await reopened.close();
      },
    );
  }
  test(
    'missing preview preference defaults on; explicitly false stays off',
    () async {
      final dir = await Directory.systemTemp.createTemp('preview-default-');
      addTearDown(() => dir.delete(recursive: true));
      final secrets = MemorySecretStore();
      final bytes = randomBytes(32);
      await secrets.write('chatprefskey:alice', b64(bytes));
      for (final explicit in [false, true]) {
        final data = <String, dynamic>{'seen': {}, 'muted': []};
        if (explicit) data['previewText'] = false;
        final encrypted = await AesGcm.with256bits().encrypt(
          utf8.encode(jsonEncode(data)),
          secretKey: SecretKey(bytes),
          aad: utf8.encode('chat-ui-v1:alice'),
        );
        await File('${dir.path}/chat-ui.enc')
            .writeAsBytes(encrypted.concatenation());
        final prefs = await LocalChatPreferences.open(
          dir: dir,
          secrets: secrets,
          uid: 'alice',
        );
        expect(prefs.previewText, !explicit);
        expect(
          prefs.needsBaseline('c'),
          isFalse,
          reason: 'an existing sidecar never migrates counts again',
        );
        await prefs.close();
      }
    },
  );
  test('legacy history is read once; new old-timestamp arrivals stay unread across reopen and reset', () async {
    final dir = await Directory.systemTemp.createTemp('unread-migration-');
    addTearDown(() => dir.delete(recursive: true));
    final secrets = MemorySecretStore();
    final prefs = await LocalChatPreferences.open(
      dir: dir,
      secrets: secrets,
      uid: 'alice',
    );
    final f = UiFixture(chatPreferences: prefs);
    await f.seed();
    addTearDown(f.session.close);
    final c = ProviderContainer(overrides: f.overrides);
    addTearDown(c.dispose);
    c.listen(chatActivityProvider, (_, _) {});
    await drain();
    expect(c.read(chatActivityProvider).unread['alice_fred'], 0);
    await f.chat.store.add(
      message(
        id: 'new-old-time',
        body: 'new arrival',
        at: fixtureTime.subtract(const Duration(days: 90)),
      ),
    );
    await drain();
    expect(c.read(chatActivityProvider).unread['alice_fred'], 1);
    expect(c.read(chatActivityProvider).arrivals.single.id, 'new-old-time');
    // A concurrent initial snapshot/reopen must never absorb a later arrival.
    await prefs.seedExisting('alice_fred', ['new-old-time']);
    expect(prefs.seen['alice_fred'], isNot(contains('new-old-time')));
    final reopened = await LocalChatPreferences.open(
      dir: dir,
      secrets: secrets,
      uid: 'alice',
    );
    expect(reopened.needsBaseline('alice_fred'), isFalse);
    expect(reopened.seen['alice_fred'], isNot(contains('new-old-time')));
    await reopened.close();
    await prefs.mute('alice_fred', true);
    await prefs.previews(false);
    await c.read(chatActivityProvider.notifier).resetPreferences();
    await drain();
    expect(c.read(chatActivityProvider).unread['alice_fred'], 0);
    expect(prefs.muted, isEmpty);
    expect(prefs.previewText, isTrue);
    expect(await f.chat.store.get('alice_fred', 'new-old-time'), isNotNull);
    await f.chat.store.add(message(id: 'after-reset', body: 'later'));
    await drain();
    expect(c.read(chatActivityProvider).unread['alice_fred'], 1);
    await prefs.close();
  });
  test(
    'racing initial snapshots cannot consume messages arriving during a write',
    () async {
      final hold = Completer<void>();
      final prefs = LocalChatPreferences(
        baselineExisting: true,
        save: (_) async => hold.future,
      );
      final first = prefs.seedExisting('c', ['old']);
      final raced = prefs.seedExisting('c', ['old', 'new']);
      await Future<void>.delayed(Duration.zero);
      expect(prefs.seen, isEmpty);
      hold.complete();
      await Future.wait([first, raced]);
      expect(prefs.seen['c'], {'old'});
      await prefs.close();
    },
  );
  test(
    'failed baseline save suppresses counts until explicit reset succeeds',
    () async {
      var fail = true;
      final prefs = LocalChatPreferences(
        baselineExisting: true,
        save: (_) async {
          if (fail) throw StateError('disk full');
        },
      );
      await expectLater(prefs.seedExisting('c', ['old']), throwsStateError);
      expect(prefs.available, isFalse);
      expect(prefs.seen, isEmpty);
      fail = false;
      await prefs.reset(
        history: {
          'c': {'old', 'current'},
        },
      );
      expect(prefs.available, isTrue);
      expect(prefs.needsBaseline('c'), isFalse);
      expect(prefs.seen['c'], {'old', 'current'});
      await prefs.close();
    },
  );
}
