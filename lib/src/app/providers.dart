// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/model/settings/local_chat_preferences.dart';

final authProvider = Provider<FirebaseAuth>((_) => FirebaseAuth.instance);
final firestoreProvider = Provider<FirebaseFirestore>(
  (_) => FirebaseFirestore.instance,
);
final secretStoreProvider = Provider<SecretStore>((_) => SecureSecretStore());
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(
    ref.watch(authProvider),
    ref.watch(firestoreProvider),
    // Never wait for a session that is still loading: signing out must not hang.
    beforeSignOut: () async {
      await ref
          .read(appSessionProvider)
          .value
          ?.pushNotifications
          ?.unregister()
          .timeout(const Duration(seconds: 3));
    },
  );
});

final authUserProvider = StreamProvider<User?>(
  (ref) => ref.watch(authProvider).authStateChanges(),
);

/// Signed in, but the account is mid-deletion (or half deleted): finish deleting.
class AccountDeletionPending implements Exception {
  AccountDeletionPending(this.uid);
  final String uid;
  @override
  String toString() => 'This account is being deleted.';
}

/// Everything that exists only while a user is signed in and keys are loaded.
class AppSession {
  AppSession({
    required this.uid,
    required this.username,
    required this.device,
    required this.chat,
    required this.keys,
    required this.safety,
    this.pushNotifications,
    LocalChatPreferences? chatPreferences,
    required StreamSubscription<void> chatsSub,
    required this.dispose,
    this.destroyLocalData,
  }) : _chatsSub = chatsSub,
       chatPreferences = chatPreferences ?? LocalChatPreferences();

  final String uid;
  final LocalChatPreferences chatPreferences;
  final String username;
  final LocalDevice device;
  final ChatService chat;
  final KeyService keys;
  final SafetyService safety;
  final PushNotificationService? pushNotifications;
  final StreamSubscription<void> _chatsSub;
  final Future<void> Function() dispose;

  /// Erases the encrypted message history and its key (account deletion).
  final Future<void> Function()? destroyLocalData;
  Future<void>? _closing;
  Future<void> close() => _closing ??= () async {
    await _chatsSub.cancel();
    await dispose();
  }();
}

final appSessionProvider = FutureProvider<AppSession?>((ref) async {
  var stopped = false;
  var initialized = false;
  var successful = false;
  Future<void>? closing;
  final cleaners = <Future<void> Function()>[];
  Future<void> cleanup() => closing ??= () async {
    stopped = true;
    Object? firstError;
    StackTrace? firstStack;
    for (final close in cleaners.reversed) {
      try {
        await close();
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
    }
    if (firstError != null) Error.throwWithStackTrace(firstError, firstStack!);
  }();
  void checkActive() {
    if (stopped || !ref.mounted) {
      throw StateError('Session initialization cancelled.');
    }
  }

  ref.onDispose(() {
    stopped = true;
    // An awaited constructor/start may still own resources; its finally block
    // closes them when it returns rather than racing that initialization.
    if (initialized) unawaited(cleanup().catchError((Object _) {}));
  });
  try {
    final user = await ref.watch(authUserProvider.future);
    checkActive();
    if (user == null) return null;
    final db = ref.watch(firestoreProvider);
    final secrets = ref.watch(secretStoreProvider);
    // An account being deleted (or left half-deleted) must not be used normally.
    // A brand-new sign-up writes its profile right after the account exists, so
    // give that a few seconds before treating a missing profile as "half deleted".
    Map<String, dynamic>? profile;
    for (var i = 0; i < 20; i++) {
      final snap = await db.collection('users').doc(user.uid).get();
      checkActive();
      if (snap.exists) {
        profile = snap.data();
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
      checkActive();
    }
    if (profile == null || profile['deleting'] == true) {
      throw AccountDeletionPending(user.uid);
    }
    // Record that the account is in use (the 13-month inactivity sweep keys off this).
    unawaited(ActivityService(db).markActiveIfDue(user.uid, profile));
    final keys = KeyService(db, secrets);
    final device = await keys.ensureDevice(user.uid);
    checkActive();
    final pushNotifications = pushEnabled
        ? PushNotificationService(
            db: db,
            uid: user.uid,
            deviceId: device.keys.deviceId,
            messaging: FirebasePushMessagingClient(),
          )
        : null;
    if (pushNotifications != null) cleaners.add(pushNotifications.unregister);
    // Only re-register silently if the user already allowed notifications.
    unawaited(
      pushNotifications?.startIfPermitted().catchError((Object _) {}) ??
          Future<void>.value(),
    );
    final prekeys = PreKeyService(db, secrets);
    await prekeys.maintain(user.uid, device); // rotate/replenish prekeys
    checkActive();
    final docs = await getApplicationDocumentsDirectory();
    checkActive();
    final store = await EncryptedFileMessageStore.open(
      dir: Directory('${docs.path}/messages_${user.uid}'),
      secrets: secrets,
      uid: user.uid,
    );
    cleaners.add(store.close);
    checkActive();
    final chatPreferences = await LocalChatPreferences.open(
      dir: Directory('${docs.path}/messages_${user.uid}'),
      secrets: secrets,
      uid: user.uid,
    );
    cleaners.add(chatPreferences.close);
    checkActive();
    final safety = SafetyService(db, secrets, user.uid);
    cleaners.add(safety.dispose);
    await safety.start();
    checkActive();
    final chat = ChatService(
      db: db,
      uid: user.uid,
      device: device,
      keys: keys,
      prekeys: prekeys,
      secrets: secrets,
      messages: store,
      safety: safety,
    );
    cleaners.add(chat.close);
    final username =
        (await db.collection('users').doc(user.uid).get()).data()?['username']
            as String? ??
        user.email?.split('@').first ??
        '';
    checkActive();

    // Decrypt in the background while the app is open, but only for chats that
    // should be live: not an unaccepted request from a stranger (so strangers
    // cannot burn through our one-time prekeys), not blocked, not hidden.
    final syncs = <String, StreamSubscription<void>>{};
    var latest = <ChatSummary>[];
    cleaners.add(() async {
      for (final sub in syncs.values.toList()) {
        await sub.cancel();
      }
      syncs.clear();
    });
    Future<void> reconcile() async {
      if (stopped) return;
      final hidden = await safety.hiddenChats();
      if (stopped) return;
      final wanted = <String>{
        for (final c in latest)
          if (!c.isIncomingRequest(user.uid) &&
              !safety.isBlocked(c.peerUid) &&
              !hidden.contains(c.chatId))
            c.chatId,
      };
      for (final id in syncs.keys.toList()) {
        if (!wanted.contains(id)) await syncs.remove(id)?.cancel();
      }
      for (final id in wanted) {
        if (stopped) return;
        if (chatPreferences.available && chatPreferences.needsBaseline(id)) {
          try {
            // Capture disk history before starting receive sync. Later network
            // arrivals must not be swallowed by first-run read bookkeeping.
            final existing = await store.watch(id).first;
            await chatPreferences.seedExisting(
              id,
              existing.where((m) => !m.outgoing).map((m) => m.id),
            );
          } catch (_) {
            // A broken UI sidecar does not stop messaging; Settings offers reset.
          }
        }
        // Baseline I/O may have yielded to a block, hide, request change or disposal.
        final nowHidden = await safety.hiddenChats();
        if (stopped) return;
        if (!latest.any(
              (c) =>
                  c.chatId == id &&
                  !c.isIncomingRequest(user.uid) &&
                  !safety.isBlocked(c.peerUid),
            ) ||
            nowHidden.contains(id)) {
          continue;
        }
        syncs.putIfAbsent(id, () => chat.startSync(id));
      }
    }

    final chatsSub = chat.watchChats().listen((chats) {
      latest = chats;
      unawaited(reconcile().catchError((Object _) {}));
    }, onError: (_) {});
    cleaners.add(chatsSub.cancel);
    final blockedSub = safety.watchBlocked().listen((_) {
      unawaited(reconcile().catchError((Object _) {}));
    });
    cleaners.add(blockedSub.cancel);
    final session = AppSession(
      uid: user.uid,
      username: username,
      device: device,
      chat: chat,
      keys: keys,
      safety: safety,
      pushNotifications: pushNotifications,
      chatPreferences: chatPreferences,
      chatsSub: chatsSub,
      destroyLocalData: () async {
        await chatPreferences.close();
        await secrets.delete('chatprefskey:${user.uid}');
        await store.destroy(secrets, user.uid);
      },
      dispose: cleanup,
    );
    successful = true;
    return session;
  } finally {
    initialized = true;
    if (!successful || stopped) await cleanup();
  }
});

final chatsProvider = StreamProvider.autoDispose<List<ChatSummary>>((ref) {
  final s = ref.watch(appSessionProvider).value;
  if (s == null) return const Stream.empty();
  return s.chat.watchChats();
});

/// Shown for a person whose account no longer exists.
const deletedAccountLabel = 'Deleted account';

final accountServiceProvider = Provider<AccountService>((ref) {
  final session = ref.read(appSessionProvider).value;
  return AccountService(
    auth: ref.watch(authProvider),
    db: ref.watch(firestoreProvider),
    secrets: ref.watch(secretStoreProvider),
    stopSession: session?.close,
    destroyLocalData: session?.destroyLocalData,
  );
});

/// Removes a conversation whose other person deleted their account.
final peerDeletedCleanupProvider = FutureProvider.autoDispose
    .family<bool, String>((ref, chatId) async {
      final s = ref.watch(appSessionProvider).value;
      return s == null ? false : s.chat.removeChatIfPeerDeleted(chatId);
    });

final peerUsernameProvider = FutureProvider.family<String, String>((
  ref,
  peerUid,
) async {
  final s = ref.watch(appSessionProvider).value;
  return (await s?.chat.usernameOf(peerUid)) ?? deletedAccountLabel;
});

final messagesProvider = StreamProvider.autoDispose
    .family<List<LocalMessage>, String>((ref, chatId) {
      final s = ref.watch(appSessionProvider).value;
      if (s == null) return const Stream.empty();
      return s.chat.watchMessages(chatId);
    });

final peerVerifiedProvider = FutureProvider.autoDispose.family<bool, String>((
  ref,
  peerUid,
) async {
  final s = ref.watch(appSessionProvider).value;
  return s == null ? false : s.keys.isVerified(peerUid);
});

/// Devices of the peer that appeared since the user last looked.
final newPeerDevicesProvider = FutureProvider.autoDispose
    .family<List<String>, String>((ref, peerUid) async {
      final s = ref.watch(appSessionProvider).value;
      if (s == null) return const [];
      try {
        return await s.keys.detectNewDevices(peerUid);
      } catch (_) {
        return const []; // identity-change errors are surfaced when sending
      }
    });

final recoveryServiceProvider = Provider<RecoveryService>((ref) {
  final db = ref.watch(firestoreProvider);
  final secrets = ref.watch(secretStoreProvider);
  return RecoveryService(db, secrets, KeyService(db, secrets));
});

final hasBackupProvider = FutureProvider.autoDispose<bool>((ref) async {
  final s = ref.watch(appSessionProvider).value;
  if (s == null) return true;
  return ref.watch(recoveryServiceProvider).hasBackup(s.uid);
});

/// The chat summary (with request state) for one chat.
final chatSummaryProvider = Provider.autoDispose.family<ChatSummary?, String>((
  ref,
  chatId,
) {
  final list = ref.watch(chatsProvider).value ?? const [];
  for (final c in list) {
    if (c.chatId == chatId) return c;
  }
  return null;
});

final blockedUidsProvider = StreamProvider.autoDispose<Set<String>>((ref) {
  final s = ref.watch(appSessionProvider).value;
  if (s == null) return const Stream.empty();
  return s.safety.watchBlocked();
});

final hiddenChatsProvider = FutureProvider.autoDispose<Set<String>>((
  ref,
) async {
  final s = ref.watch(appSessionProvider).value;
  return s == null ? <String>{} : s.safety.hiddenChats();
});

/// Contacts whose identity key changed (messages are held until the user decides).
final identityAlertsProvider =
    StreamProvider.autoDispose<Map<String, List<int>>>((ref) {
      final s = ref.watch(appSessionProvider).value;
      if (s == null) return const Stream.empty();
      return s.chat.watchIdentityAlerts();
    });
