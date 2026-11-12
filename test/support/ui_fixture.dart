// Test/render-only fixtures. No Firebase SDK instance, real keys or platform storage.
import 'dart:async';

import 'package:fireplace/src/db/message_quote.dart';
import 'package:fireplace/src/model/chat/message_limits.dart';

import 'dart:typed_data';

import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/settings/local_chat_preferences.dart';
import 'package:fireplace/src/model/chat/message_controls.dart';
import 'package:fireplace/src/db/message_mutation.dart';
import 'package:fireplace/src/crypto/device.dart';
import 'package:fireplace/src/crypto/identity.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

final fixtureTime = DateTime(2026, 10, 4, 12);

class _Identity extends Fake implements AccountIdentity {
  @override
  Uint8List get publicBytes => Uint8List.fromList(List.generate(64, (i) => i));
}

class _Device extends Fake implements DeviceKeys {
  @override
  String get deviceId => 'example-device-alice';
}

class FixtureKeys extends Fake implements KeyService {
  @override
  void bindLocalDevice(String uid, LocalDevice device) {}

  @override
  Future<List<int>?> pinnedIdentity(String peerUid) async =>
      List.generate(64, (i) => 63 - i);
  @override
  Future<List<DeviceInfo>> listOwnDevices(
    String uid,
    String thisDeviceId,
  ) async => [
    DeviceInfo(thisDeviceId, fixtureTime, false, true),
    DeviceInfo('example-second-device', fixtureTime, false, false),
  ];
}

class FixtureSafety extends Fake implements SafetyService {}

class FixtureChat extends Fake implements ChatService {
  final store = MemoryMessageStore();
  List<ChatSummary> summaries = [];
  final sends = <String>[];
  final starts = <String>[];
  Completer<void>? sendHold;
  Completer<String>? startHold;
  Completer<void>? controlHold;
  Object? sendError;
  Object? controlError;
  int controlAttempts = 0;
  final reactions = <(String, String)>[];
  final remoteDeletes = <String>[];

  @override
  String peerOf(String chatId) => chatId.split('_').last;
  @override
  void prepareToSend(String chatId) {}
  @override
  Stream<List<ChatSummary>> watchChats() => Stream.value(summaries);
  @override
  Stream<List<LocalMessage>> watchMessages(String chatId) {
    final incoming = summaries.any(
      (c) => c.chatId == chatId && !c.accepted && c.initiator != 'alice',
    );
    return incoming ? Stream.value([]) : store.watch(chatId);
  }

  @override
  Future<void> sendText(String chatId, String body) async {
    sends.add(body);
    if (sendHold != null) await sendHold!.future;
    if (sendError != null) throw sendError!;
  }

  final edits = <(String, String)>[];
  @override
  Future<void> editMessage(String chatId, String targetId, String body) async {
    controlAttempts++;
    if (controlError != null) throw controlError!;
    final target = await store.get(chatId, targetId);
    edits.add((targetId, body));
    await store.add(
      LocalMessage(
        id: 'edit-${edits.length}',
        chatId: chatId,
        senderUid: 'alice',
        senderDevice: 'example-device-alice',
        outgoing: true,
        sentAt: fixtureTime,
        body: '',
        mutation: MessageMutation(
          kind: MessageMutationKind.edit,
          targetId: targetId,
          body: body,
          revision: target!.editClock + 1,
        ),
      ),
    );
  }

  final replies = <(String, String)>[];
  @override
  Future<void> sendReply(String chatId, String body, String targetId) async {
    await sendText(chatId, body);
    replies.add((targetId, body));
    final target = await store.get(chatId, targetId);
    await store.add(
      LocalMessage(
        id: 'reply-${replies.length}',
        chatId: chatId,
        senderUid: 'alice',
        senderDevice: 'example-device-alice',
        outgoing: true,
        sentAt: fixtureTime.add(const Duration(minutes: 1)),
        body: body,
        quote: MessageQuote(
          targetId: targetId,
          senderUid: target!.senderUid,
          body: clipMessage(target.body, 1024),
        ),
      ),
    );
  }

  @override
  Future<void> deleteMessageLocally(String chatId, String messageId) =>
      store.remove(chatId, messageId);

  @override
  Future<void> react(String chatId, String targetId, String emoji) async {
    controlAttempts++;
    if (controlHold != null) await controlHold!.future;
    if (controlError != null) throw controlError!;
    reactions.add((targetId, emoji));
    final target = await store.get(chatId, targetId);
    final previous = target?.reactions['alice'];
    await store.add(
      LocalMessage(
        id: 'reaction-${reactions.length}',
        chatId: chatId,
        senderUid: 'alice',
        senderDevice: 'example-device-alice',
        outgoing: true,
        sentAt: fixtureTime,
        body: '',
        mutation: MessageMutation(
          kind: MessageMutationKind.reaction,
          targetId: targetId,
          emoji: emoji,
          revision: (previous?.revision ?? 0) + 1,
          operation: previous?.emoji == emoji
              ? ReactionOperation.clear
              : ReactionOperation.set,
        ),
      ),
    );
  }

  @override
  Future<void> deleteForEveryone(String chatId, String targetId) async {
    if (controlError != null) throw controlError!;
    remoteDeletes.add(targetId);
    await store.add(
      LocalMessage(
        id: 'delete-${remoteDeletes.length}',
        chatId: chatId,
        senderUid: 'alice',
        senderDevice: 'example-device-alice',
        outgoing: true,
        sentAt: fixtureTime,
        body: '',
        mutation: MessageMutation(
          kind: MessageMutationKind.delete,
          targetId: targetId,
        ),
      ),
    );
  }

  @override
  Future<String> startChat(String username) async {
    starts.add(username);
    return startHold?.future ?? Future.value('alice_$username');
  }
}

class UiFixture {
  UiFixture({
    FixtureChat? chat,
    FixtureKeys? keys,
    FixtureSafety? safety,
    MemorySecretStore? secrets,
    LocalChatPreferences? chatPreferences,
    this.pushNotifications,
    this.overrideAuth = true,
  }) : chat = chat ?? FixtureChat(),
       keys = keys ?? FixtureKeys(),
       safety = safety ?? FixtureSafety(),
       secrets = secrets ?? MemorySecretStore() {
    final device = LocalDevice(
      _Identity(),
      _Device(),
      DeviceBundle(
        uid: 'alice',
        deviceId: 'example-device-alice',
        x25519Pub: Uint8List(32),
        kemPub: Uint8List(0),
        identityPub: Uint8List(64),
        cert: Uint8List(0),
      ),
    );
    session = AppSession(
      uid: 'alice',
      username: 'alice',
      device: device,
      chat: this.chat,
      keys: this.keys,
      safety: this.safety,
      chatPreferences: chatPreferences,
      pushNotifications: pushNotifications,
      chatsSub: const Stream<void>.empty().listen((_) {}),
      dispose: () async {},
    );
  }
  final FixtureChat chat;
  final FixtureKeys keys;

  /// Shown in Settings → Notifications when present.
  final PushNotificationService? pushNotifications;
  final FixtureSafety safety;
  final bool overrideAuth;
  bool hasBackup = false, verified = false;

  /// The app's clock in this fixture; a test may move it on.
  DateTime now = fixtureTime;
  Map<String, List<int>> alerts = {};
  List<String> freshDevices = [];
  Set<String> blocked = {};
  Set<String> hidden = {};
  Future<Set<String>>? hiddenFuture;
  final names = <String, Future<String>>{};
  late final AppSession session;
  final MemorySecretStore secrets;
  List<Override> get overrides => [
    appSessionProvider.overrideWithValue(AsyncData(session)),
    messageControlNowProvider.overrideWithValue(() => now),
    secretStoreProvider.overrideWithValue(secrets),
    peerUsernameProvider.overrideWith(
      (ref, peer) => names[peer] ?? Future.value(peer),
    ),
    peerVerifiedProvider.overrideWith((ref, peer) async => verified),
    newPeerDevicesProvider.overrideWith((ref, peer) async => freshDevices),
    identityAlertsProvider.overrideWith((ref) => Stream.value(alerts)),
    blockedUidsProvider.overrideWith((ref) => Stream.value(blocked)),
    hiddenChatsProvider.overrideWith(
      (ref) => hiddenFuture ?? Future.value(hidden),
    ),
    hasBackupProvider.overrideWith((ref) async => hasBackup),
    if (overrideAuth) authUserProvider.overrideWithValue(const AsyncData(null)),
  ];

  Future<void> seed() async {
    chat.summaries = [
      ChatSummary('alice_fred', 'fred', fixtureTime),
      ChatSummary(
        'alice_bob',
        'bob',
        fixtureTime.subtract(const Duration(days: 1)),
      ),
      ChatSummary(
        'alice_theo',
        'theo',
        fixtureTime,
        initiator: 'theo',
        accepted: false,
      ),
    ];
    for (final (id, outgoing, at, body) in [
      (
        '1',
        false,
        fixtureTime.subtract(const Duration(days: 1)),
        'Are we still on for Saturday?',
      ),
      (
        '2',
        true,
        fixtureTime.subtract(const Duration(days: 1)),
        'Of course. I can bring dessert.',
      ),
      (
        '3',
        false,
        fixtureTime.subtract(const Duration(minutes: 8)),
        'Perfect. See you in the garden ☕',
      ),
      (
        '4',
        true,
        fixtureTime.subtract(const Duration(minutes: 4)),
        'Looking forward to it. What time works for you?',
      ),
      ('5', false, fixtureTime, 'Around two? There is no rush.'),
    ]) {
      await chat.store.add(
        message(id: id, outgoing: outgoing, at: at, body: body),
      );
    }
  }
}

LocalMessage message({
  required String id,
  required String body,
  bool outgoing = false,
  DateTime? at,
  MessageStatus status = MessageStatus.ok,
}) => LocalMessage(
  id: id,
  chatId: 'alice_fred',
  senderUid: outgoing ? 'alice' : 'fred',
  senderDevice: 'example-device',
  outgoing: outgoing,
  sentAt: at ?? fixtureTime,
  body: body,
  status: status,
);

/// Explicit pumps also work for screens with an indeterminate loading indicator.
Future<void> settleUi(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
}

/// A notifications service over an in-memory Firestore, with the system
/// permission already granted. For settings renders and tests.
PushNotificationService fixturePush() => PushNotificationService(
  db: FakeFirebaseFirestore(),
  uid: 'alice',
  deviceId: 'example-device-alice',
  messaging: _FixturePushMessaging(),
  isApplePlatform: false,
  platform: 'ios',
);

class _FixturePushMessaging implements PushMessagingClient {
  @override
  Future<PushPermission> permissionStatus() async => PushPermission.allowed;
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<String?> getApnsToken() async => 'example-apns-token';
  @override
  Future<String?> getToken() async => 'example-fcm-token-0123456789';
  @override
  Stream<String> get onTokenRefresh => const Stream.empty();
  @override
  Future<void> setForegroundPresentation() async {}
}
