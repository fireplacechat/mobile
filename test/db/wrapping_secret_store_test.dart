// The passphrase lock's store (decision 0033): wrapped items are AES-GCM under
// the data key, tied to their name, and unreadable without it; everything else
// passes through as before.
import 'package:cryptography/cryptography.dart';
import 'package:fireplace/src/db/secret_store.dart';
import 'package:fireplace/src/db/wrapping_secret_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final key = List.generate(32, (i) => i);
  late MemorySecretStore inner;
  late WrappingSecretStore store;
  setUp(() {
    inner = MemorySecretStore();
    store = WrappingSecretStore(inner);
  });

  void open({bool wrapWrites = true}) => store.open(
    uid: 'alice',
    deviceId: 'dev1',
    dataKey: key,
    wrapWrites: wrapWrites,
  );

  test('the items wrapped are the ones that open data, for that account', () {
    for (final name in [
      'msgkey:alice',
      'chatprefskey:alice',
      'groupkey:alice',
      'identity:alice',
      'device:alice',
      'prekeys:alice:dev1',
      'sess:dev1:bob:dev9',
      'journal:dev1',
      'journals:dev1',
      'journal:dev1:old',
    ]) {
      expect(lockWrapsItem(name, 'alice', 'dev1'), isTrue, reason: name);
    }
    for (final name in [
      'msgkey:bob',
      'sess:dev2:bob:dev9',
      'bundle:alice',
      'cursor:dev1:alice_bob',
      'pushnopreview:alice',
      'passlock:alice',
      'passlockpepper:alice',
      'pin:account:["alice","bob"]',
      'peercolors:alice',
    ]) {
      expect(lockWrapsItem(name, 'alice', 'dev1'), isFalse, reason: name);
    }
  });

  test('without a data key everything passes through as before', () async {
    await store.write('identity:alice', 'secret');
    expect(inner.data['identity:alice'], 'secret');
    expect(await store.read('identity:alice'), 'secret');
  });

  test('open, a wrapped item is stored sealed and read back plain', () async {
    open();
    await store.write('identity:alice', 'secret');
    await store.write('cursor:dev1:alice_bob', '1:2');
    expect(inner.data['identity:alice'], startsWith(wrappedSecretPrefix));
    expect(inner.data['identity:alice'], isNot(contains('secret')));
    expect(inner.data['cursor:dev1:alice_bob'], '1:2');
    expect(await store.read('identity:alice'), 'secret');
    expect((await store.readAll())['identity:alice'], 'secret');
  });

  test('closed, a wrapped item cannot be read', () async {
    open();
    await store.write('sess:dev1:bob:dev9', '[]');
    store.close();
    await expectLater(
      store.read('sess:dev1:bob:dev9'),
      throwsA(isA<SecretsLocked>()),
    );
    // Erasure by name still sees it.
    expect((await store.readAll()).keys, contains('sess:dev1:bob:dev9'));
  });

  test('a wrapped value moved to another name does not open', () async {
    open();
    await store.write('identity:alice', 'secret');
    inner.data['device:alice'] = inner.data['identity:alice']!;
    await expectLater(
      store.read('device:alice'),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test('rewrite wraps and unwraps in place, and keeps a newer write', () async {
    await store.write('msgkey:alice', 'k1');
    open();
    // A write made while the rewrite waits its turn is not undone by it.
    final rewrite = store.rewrite('msgkey:alice', wrapped: true);
    final write = store.write('msgkey:alice', 'k2');
    await Future.wait([rewrite, write]);
    expect(inner.data['msgkey:alice'], startsWith(wrappedSecretPrefix));
    expect(await store.read('msgkey:alice'), 'k2');

    store.stopWrapping();
    await store.rewrite('msgkey:alice', wrapped: false);
    expect(inner.data['msgkey:alice'], 'k2');
    await store.write('msgkey:alice', 'k3');
    expect(inner.data['msgkey:alice'], 'k3');
  });

  test('coveredItems lists only the open account\'s wrapped items', () async {
    inner.data.addAll({
      'identity:alice': 'a',
      'sess:dev1:bob:dev9': 'b',
      'identity:bob': 'c',
      'cursor:dev1:x': 'd',
    });
    await expectLater(store.coveredItems(), throwsA(isA<SecretsLocked>()));
    open();
    expect((await store.coveredItems()).toSet(), {
      'identity:alice',
      'sess:dev1:bob:dev9',
    });
  });

  test('seal opens only with its own key and label', () async {
    final sealed = await WrappingSecretStore.seal(key, [1, 2, 3], 'label');
    expect(await WrappingSecretStore.unseal(key, sealed, 'label'), [1, 2, 3]);
    await expectLater(
      WrappingSecretStore.unseal(List.filled(32, 9), sealed, 'label'),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
    await expectLater(
      WrappingSecretStore.unseal(key, sealed, 'other'),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });
}
