import 'package:fireplace/fireplace_crypto.dart';
import 'package:fireplace/src/model/chat/chat_tuning.dart';
import 'package:fireplace/src/model/chat/session_store.dart';
import 'package:fireplace/src/model/keys/key_service.dart';
import 'package:fireplace/src/model/keys/prekey_service.dart';

/// One message encrypted for each device it goes to.
typedef SealedMessage = ({
  /// Envelope JSON by device id: the `envelopes` field of the message.
  Map<String, dynamic> envelopes,

  /// The sessions each envelope advanced, not saved yet.
  List<AdvancedSessions> advanced,

  /// Why a device got no envelope (it has published no prekeys).
  List<String> skipped,
});

/// Encrypts [plain] for every device in [targets], picking or starting a
/// session for each. The advanced ratchets are returned, NOT saved: if the
/// message is never published, its keys must not be used up.
Future<SealedMessage> encryptForDevices({
  required SessionStore sessions,
  required PreKeyService prekeys,
  required LocalDevice device,
  required Iterable<DeviceBundle> targets,
  required List<int> plain,
  required String chatId,
}) async {
  final envelopes = <String, dynamic>{};
  final skipped = <String>[];
  final advanced = <AdvancedSessions>[];
  for (final target in targets) {
    final held = await sessions.loadSessions(target.uid, target.deviceId);
    var preferred = SessionStore.pickSession(held);
    // A session we started that was never answered may be lost (the peer
    // lost the matching prekey): start a fresh one, keep the old for late
    // replies.
    final stale =
        preferred != null &&
        !preferred.acknowledged &&
        DateTime.now().difference(preferred.createdAt) >
            ChatTuning.staleSessionAfter;
    if (preferred == null || stale) {
      try {
        final bundle = await prekeys.fetchBundle(
          target,
          claimer: device.bundle.uid,
        );
        final (s, _) = await Session.initiate(
          local: device.keys,
          localBundle: device.bundle,
          remote: bundle,
        );
        held.add(s);
        preferred = s;
      } on PreKeyException catch (e) {
        // A device that never published prekeys (old install, never opened)
        // must not block delivery to the contact's other devices.
        if (preferred == null) {
          skipped.add(e.message);
          continue;
        }
        // otherwise keep using the older session
      }
      // forget long-dead unanswered sessions
      held.removeWhere(
        (x) =>
            x != preferred &&
            !x.acknowledged &&
            DateTime.now().difference(x.createdAt) > ChatTuning.pruneAfter,
      );
    }
    final env = await preferred.encrypt(plain, chatId: chatId);
    advanced.add((uid: target.uid, deviceId: target.deviceId, sessions: held));
    envelopes[target.deviceId] = env.toJson();
  }
  return (envelopes: envelopes, advanced: advanced, skipped: skipped);
}
