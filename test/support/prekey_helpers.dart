import 'package:fireplace/fireplace_crypto.dart';

/// A device's published prekeys plus the private halves, for crypto-level tests.
class PreKeyed {
  PreKeyed(this.bundle, this.spk, this.opk, this.identity);
  final DeviceBundle bundle;
  final PreKeyRecord spk;
  final PreKeyRecord? opk;
  final AccountIdentity identity;

  Future<PreKeyBundle> claim({bool withOneTime = true}) async => PreKeyBundle(
    device: bundle,
    signed: await PreKeys.sign(spk, identity, bundle.uid, bundle.deviceId),
    oneTime: withOneTime && opk != null ? PreKeys.oneTime(opk!) : null,
  );
}

Future<PreKeyed> preKeyed(
  DeviceBundle bundle,
  AccountIdentity identity, {
  bool withOneTime = true,
}) async => PreKeyed(
  bundle,
  await PreKeyRecord.generate(),
  withOneTime ? await PreKeyRecord.generate() : null,
  identity,
);
