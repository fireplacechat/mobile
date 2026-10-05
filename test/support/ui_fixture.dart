// Test/render-only fixtures. No Firebase SDK instance, real keys or platform storage.
import 'dart:async';
import 'dart:typed_data';

import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/services/local_chat_preferences.dart';
import 'package:fireplace/src/crypto/device.dart';
import 'package:fireplace/src/crypto/identity.dart';
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
  Object? sendError;

  @override
  String peerOf(String chatId) => chatId.split('_').last;
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
    LocalChatPreferences? chatPreferences,
    this.overrideAuth = true,
  }) : chat = chat ?? FixtureChat(),
       keys = keys ?? FixtureKeys(),
       safety = safety ?? FixtureSafety() {
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
      chatsSub: const Stream<void>.empty().listen((_) {}),
      dispose: () async {},
    );
  }
  final FixtureChat chat;
  final FixtureKeys keys;
  final FixtureSafety safety;
  final bool overrideAuth;
  bool hasBackup = false, verified = false;
  Map<String, List<int>> alerts = {};
  List<String> freshDevices = [];
  Set<String> blocked = {};
  Set<String> hidden = {};
  Future<Set<String>>? hiddenFuture;
  final names = <String, Future<String>>{};
  late final AppSession session;
  List<Override> get overrides => [
    appSessionProvider.overrideWithValue(AsyncData(session)),
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
