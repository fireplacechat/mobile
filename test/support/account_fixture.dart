// Offline action fakes; no real recovery material or service connection.
import 'dart:async';

import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/crypto/identity.dart';
import 'package:fireplace/src/crypto/link.dart';
import 'package:fireplace/src/crypto/recovery.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_fixture.dart';

class ActionKeys extends FixtureKeys {
  int removals = 0, loads = 0;
  Completer<void>? hold;
  Object? error;
  @override
  Future<List<DeviceInfo>> listOwnDevices(String uid, String deviceId) async {
    loads++;
    return super.listOwnDevices(uid, deviceId);
  }

  @override
  Future<void> revokeDevice(
    String uid,
    String deviceId, {
    required String thisDeviceId,
  }) async {
    removals++;
    if (hold != null) await hold!.future;
    if (error != null) throw error!;
  }
}

class ActionAuth extends Fake implements AuthService {
  int passwords = 0, signouts = 0;
  Completer<void>? hold;
  Object? error;
  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    passwords++;
    if (hold != null) await hold!.future;
    if (error != null) throw error!;
  }

  @override
  Future<void> signOut() async {
    signouts++;
    if (hold != null) await hold!.future;
    if (error != null) throw error!;
  }
}

class _ExampleKey extends Fake implements RecoveryKey {
  @override
  Future<String> display() async => 'EXAMPLE KEY — NOT A VALID RECOVERY KEY';
}

class ActionRecovery extends Fake implements RecoveryService {
  int creations = 0, approvals = 0, starts = 0, restores = 0, completions = 0;
  final canceled = <LinkRequest>[];
  Completer<void>? hold;
  Completer<LinkRequest>? startHold;
  Completer<SealedIdentity>? response;
  Object? error;
  late LinkRequest request;
  late LocalDevice device;
  @override
  Future<RecoveryKey> createBackup(String uid, AccountIdentity identity) async {
    creations++;
    if (hold != null) await hold!.future;
    if (error != null) throw error!;
    return _ExampleKey();
  }

  @override
  Future<String> approveLink(
    String uid,
    AccountIdentity identity,
    String raw,
  ) async {
    approvals++;
    if (hold != null) await hold!.future;
    if (error != null) throw error!;
    return '123456';
  }

  @override
  Future<LocalDevice> restoreWithRecoveryKey(String uid, String input) async {
    restores++;
    if (hold != null) await hold!.future;
    if (error != null) throw error!;
    return device;
  }

  @override
  Future<LinkRequest> startLink(String uid) async {
    starts++;
    return startHold?.future ?? Future.value(request);
  }

  @override
  Future<SealedIdentity> awaitResponse(
    LinkRequest req, {
    Duration timeout = const Duration(minutes: 10),
  }) async => response!.future;
  @override
  Future<void> cancelLink(LinkRequest req) async {
    canceled.add(req);
  }

  @override
  Future<LocalDevice> completeLink(
    LinkRequest req,
    SealedIdentity sealed,
    String code,
  ) async {
    completions++;
    if (hold != null) await hold!.future;
    if (error != null) throw error!;
    return device;
  }
}
