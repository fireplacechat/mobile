import 'dart:convert';

import 'package:fireplace/fireplace_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final backend in CryptoBackendKind.values) {
    testWidgets('${backend.name}: send and receive time', (tester) async {
      await tester.runAsync(
        () => CryptoBackend.runWith(backend, () async {
          final ai = await AccountIdentity.generate(),
              bi = await AccountIdentity.generate();
          final ak = await DeviceKeys.generate(),
              bk = await DeviceKeys.generate();
          final ab = await ak.certify(ai, 'alice'),
              bb = await bk.certify(bi, 'bob');
          final record = await PreKeyRecord.generate();
          final signed = await PreKeys.sign(record, bi, 'bob', bk.deviceId);
          final (a, hs) = await Session.initiate(
            local: ak,
            localBundle: ab,
            remote: PreKeyBundle(device: bb, signed: signed),
          );
          final b = await Session.accept(
            local: bk,
            localBundle: bb,
            remote: ab,
            handshake: hs,
            signedPreKey: record,
          );
          final sends = <int>[], receives = <int>[];
          try {
            for (var i = 0; i < 44; i++) {
              final from = i.isEven ? a : b, to = i.isEven ? b : a;
              final payload = utf8.encode('fictional benchmark payload $i');
              final watch = Stopwatch()..start();
              final envelope = await from.encrypt(payload, chatId: 'benchmark');
              final send = watch.elapsedMicroseconds;
              watch.reset();
              final plaintext = await to.decrypt(envelope, chatId: 'benchmark');
              final receive = watch.elapsedMicroseconds;
              watch.stop();
              expect(plaintext, payload);
              if (i >= 4) {
                sends.add(send);
                receives.add(receive);
              }
            }
          } finally {
            a.close();
            b.close();
          }
          Map<String, num> stats(List<int> values) {
            values.sort();
            return {
              'count': values.length,
              'mean_us': values.reduce((a, b) => a + b) / values.length,
              'p50_us': values[values.length ~/ 2],
              'p95_us': values[(values.length * .95).ceil() - 1],
            };
          }

          // Only aggregate timing values are printed. No keys, tokens, sessions,
          // envelopes, message content or device identifiers enter the log.
          // ignore: avoid_print
          print(
            'CRYPTO_BENCHMARK ${jsonEncode({'backend': backend.name, 'send': stats(sends), 'receive': stats(receives)})}',
          );
        }),
      );
    }, tags: 'timing');
  }
}
