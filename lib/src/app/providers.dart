// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:fireplace/src/app/chat_color_preference.dart';
import 'package:fireplace/src/model/groups/group_models.dart'
    show groupsEnabled;
import 'package:fireplace/src/model/groups/group_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/scheduler.dart';
import 'package:fireplace/src/model/chat/peer_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:fireplace/fireplace_services.dart';
import 'package:fireplace/src/app/account_history.dart';
import 'package:fireplace/src/model/account/profile_ready.dart';
import 'package:fireplace/src/model/chat/chat_sync_coordinator.dart';
import 'package:fireplace/src/model/common/session_scope.dart';
import 'package:fireplace/src/model/notifications/arrival_notifier.dart';
import 'package:fireplace/src/model/notifications/preview_notifier.dart';
import 'package:fireplace/src/model/push/push_chat_index.dart';
import 'package:fireplace/src/model/push/preview_credentials.dart';
import 'package:fireplace/src/model/safety/push_challenge.dart';
import 'package:fireplace/src/model/settings/local_chat_preferences.dart';
import 'package:fireplace/src/model/settings/account_preferences.dart';
import 'package:fireplace/src/db/account_erasure.dart';
import 'package:fireplace/src/db/ios_shared_storage.dart';

final authProvider = Provider<FirebaseAuth>((_) => FirebaseAuth.instance);
final firestoreProvider = Provider<FirebaseFirestore>(
  (_) => FirebaseFirestore.instance,
);
final secretStoreProvider = Provider<SecretStore>((_) => SecureSecretStore());
final accountPreferencesProvider = Provider<AccountPreferences>(
  (ref) => AccountPreferences(ref.watch(secretStoreProvider)),
);
final preferencesUidProvider = Provider<String?>((ref) {
  // UI-only test harnesses need no Firebase platform plugin.
  try {
    final auth = ref.watch(authProvider);
    ref.watch(authUserProvider);
    return auth.currentUser?.uid;
  } catch (_) {
    return null;
  }
});
final accountErasureDirectoriesProvider =
    Provider<Future<List<Directory>> Function()>(
      (_) => () async {
        final roots = [await getApplicationDocumentsDirectory()];
        if (Platform.isIOS) {
          roots.add(Directory((await IosSharedStorage.prepare()).directory));
        }
        return roots;
      },
    );
final iosPreviewCredentialsProvider = Provider<IosPreviewCredentials?>((ref) {
  if (!Platform.isIOS) return null;
  final credentials = IosPreviewCredentials(
    ref.watch(authProvider),
    ref.watch(secretStoreProvider),
  )..start();
  ref.onDispose(() => unawaited(credentials.close().catchError((Object _) {})));
  return credentials;
});
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(
    ref.watch(authProvider),
    ref.watch(firestoreProvider),
    beforeLocalSignOut: () async =>
        ref.read(iosPreviewCredentialsProvider)?.beforeLocalSignOut(),
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

/// The platform push plugin, or null when push is compiled out. Tests
/// override it so no Firebase plugin is touched.
final pushMessagingClientProvider = Provider<PushMessagingClient?>(
  (_) => pushEnabled ? FirebasePushMessagingClient() : null,
);

final authUserProvider = StreamProvider<User?>((ref) {
  ref.watch(iosPreviewCredentialsProvider);
  return ref.watch(authProvider).authStateChanges();
});

/// The lock this account's stores share between the app and the background
/// push handler: a name in the isolate name server, and a generation file next
/// to the history (decision 0030).
SharedLock accountLock(
  String uid,
  Directory historyDir, {
  bool generation = true,
}) => SharedLock(
  gate: Platform.isIOS
      ? CrossProcessLockGate(
          File('${historyDir.parent.path}/locks/$uid.lock'),
          isolateGate: IsolateLockGate('fireplace.account.$uid'),
        )
      : IsolateLockGate('fireplace.account.$uid'),
  generation: generation
      ? FileLockGeneration(File('${historyDir.path}/lock.gen'))
      : null,
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
    this.groups,
    this.peerColors,
    LocalChatPreferences? chatPreferences,
    required StreamSubscription<void> chatsSub,
    required this.dispose,
    this.destroyLocalData,
  }) : _chatsSub = chatsSub,
       chatPreferences = chatPreferences ?? LocalChatPreferences();

  /// The colours the people this account chats with chose (decision 0052).
  final PeerColors? peerColors;

  final String uid;
  final LocalChatPreferences chatPreferences;
  final String username;
  final LocalDevice device;
  final ChatService chat;
  final KeyService keys;
  final SafetyService safety;
  final PushNotificationService? pushNotifications;

  /// Group chats (decision 0050); null unless built with FIREPLACE_GROUPS.
  final GroupService? groups;
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
  final scope = SessionScope(isMounted: () => ref.mounted);
  ref.onDispose(scope.disposed);
  try {
    // 1. Resolve the signed-in account.
    final user = await ref.watch(authUserProvider.future);
    scope.checkActive();
    if (user == null) return null;
    final db = ref.watch(firestoreProvider);
    final secrets = ref.watch(secretStoreProvider);
    // 2. Wait for the account profile.
    // An account being deleted (or left half-deleted) must not be used normally.
    // Sign-up creates the Auth user, which starts this session, and only then
    // writes the profile. The first reads are also refused until the ID token
    // is attached. Wait that out. A confirmed miss is still "half deleted".
    final profile = await waitForOwnProfile(
      ensureCredential: () => user.getIdToken().then((_) {}),
      read: () async {
        final snap = await db.collection('users').doc(user.uid).get();
        return ProfileRead(exists: snap.exists, data: snap.data());
      },
      justCreated: justCreatedAccount(user),
      checkActive: scope.checkActive,
    );
    if (profile == null || profile['deleting'] == true) {
      throw AccountDeletionPending(user.uid);
    }
    // 3. Record activity and load device keys.
    // Record that the account is in use (the 13-month inactivity sweep keys off this).
    unawaited(ActivityService(db).markActiveIfDue(user.uid, profile));
    final keys = KeyService(db, secrets);
    final device = await keys.ensureDevice(user.uid);
    scope.checkActive();
    // 4. Notifications: the first signed-in launch shows the system prompt;
    // later launches re-register silently unless the user turned them off.
    final messaging = ref.watch(pushMessagingClientProvider);
    final pushNotifications = messaging == null
        ? null
        : PushNotificationService(
            db: db,
            uid: user.uid,
            deviceId: device.keys.deviceId,
            messaging: messaging,
            preferences: secrets,
          );
    if (pushNotifications != null) scope.add(pushNotifications.unregister);
    unawaited(
      pushNotifications?.startAtLaunch().catchError((Object _) {}) ??
          Future<void>.value(),
    );
    // 5. The account lock, shared with the background push handler's isolate
    // (decision 0030), and prekey upkeep. A new device has published nothing
    // yet, so nobody could start a conversation with it: wait for its first
    // keys. Otherwise rotating and refilling runs in the background (it is
    // safe alongside receiving) instead of holding up the chat list.
    final docs = await getApplicationDocumentsDirectory();
    scope.checkActive();
    final historyDir = await accountHistoryDirectory(user.uid, docs);
    await historyDir.create(recursive: true);
    final lock = accountLock(user.uid, historyDir);
    scope.add(() async => lock.close());
    final prekeys = PreKeyService(db, secrets, lock: lock);
    if (!await prekeys.hasSignedPreKey(user.uid, device.keys.deviceId)) {
      await prekeys.maintain(user.uid, device);
    } else {
      unawaited(
        prekeys
            .maintain(user.uid, device, isStopped: () => scope.stopped)
            .catchError((Object _) {}),
      );
    }
    scope.checkActive();
    // 6. Open local history and preferences.
    final store = await EncryptedFileMessageStore.open(
      dir: historyDir,
      secrets: secrets,
      uid: user.uid,
      lock: lock,
    );
    scope.add(store.close);
    scope.checkActive();
    final chatPreferences = await LocalChatPreferences.open(
      dir: historyDir,
      secrets: secrets,
      uid: user.uid,
    );
    scope.add(chatPreferences.close);
    scope.checkActive();
    // 7. Start safety state and the chat service.
    final safety = SafetyService(db, secrets, user.uid);
    scope.add(safety.dispose);
    await safety.start();
    scope.checkActive();
    // One colour per person (decision 0052): this account's goes out inside
    // its messages, and other people's are remembered as theirs arrive.
    final peerColors = PeerColors(secrets, user.uid);
    await peerColors.load();
    scope.add(peerColors.close);
    final chat = ChatService(
      db: db,
      uid: user.uid,
      device: device,
      keys: keys,
      prekeys: prekeys,
      secrets: secrets,
      messages: store,
      safety: safety,
      lock: lock,
      ownColor: () => ref.read(chatBubbleColorsProvider).outgoing.name,
      onPeerColor: peerColors.note,
    );
    scope.add(chat.close);
    // 8. Resolve the display username from the profile read in step 2.
    final username =
        profile['username'] as String? ?? user.email?.split('@').first ?? '';

    // 9. Coordinate background sync and subscribe to eligibility changes.
    // Decrypt in the background while the app is open, but only for chats that
    // should be live: not an unaccepted request from a stranger (so strangers
    // cannot burn through our one-time prekeys), not blocked, not hidden.
    // The chats it receives are also the ones the push handler may receive.
    final pushChats = messaging == null
        ? null
        : PushChatIndex(secrets, user.uid);
    final coordinator = ChatSyncCoordinator(
      uid: user.uid,
      safety: safety,
      chat: chat,
      chatPreferences: chatPreferences,
      store: store,
      isStopped: () => scope.stopped,
      onLiveChats: pushChats == null
          ? null
          : (ids) => unawaited(pushChats.save(ids).catchError((Object _) {})),
    );
    scope.add(coordinator.stop);
    final chatsSub = chat.watchChats().listen(
      (chats) => coordinator.chatsChanged(chats),
      onError: (_) {},
    );
    scope.add(chatsSub.cancel);
    final blockedSub = safety.watchBlocked().listen((_) {
      coordinator.blockedChanged();
    });
    scope.add(blockedSub.cancel);
    if (messaging != null) {
      // Android: while the app is alive but not on screen, it posts what it
      // receives itself (decision 0030).
      if (Platform.isAndroid) {
        final arrivals = ArrivalNotifier(
          arrivals: chat.arrivals,
          uid: user.uid,
          prefs: secrets,
          store: store,
          notifier: PreviewNotifier(const NativeNotificationPoster()),
          onScreen: () =>
              SchedulerBinding.instance.lifecycleState ==
              AppLifecycleState.resumed,
          usernameOf: (chatId) => chat.usernameOf(chat.peerOf(chatId)),
        );
        scope.add(arrivals.close);
      }
      // A push challenge (backend decision 0020) while the app is open.
      final challenges = PushChallenge(db);
      final onMessage = FirebaseMessaging.onMessage.listen(
        (m) => unawaited(
          challenges.answer({
            for (final e in m.data.entries) e.key: '${e.value}',
          }, user.uid),
        ),
        onError: (Object _) {},
      );
      scope.add(onMessage.cancel);
    }
    // 9b. Group chats (decision 0050), only in builds with FIREPLACE_GROUPS.
    // A failure here leaves groups unavailable and 1:1 chats untouched.
    GroupService? groups;
    if (groupsEnabled) {
      try {
        final service = GroupService(
          db: db,
          uid: user.uid,
          device: device,
          secrets: secrets,
          historyDir: historyDir,
          messages: store,
        )..ownColor = ref.read(chatBubbleColorsProvider).outgoing.name;
        await service.start();
        scope.add(service.close);
        groups = service;
      } catch (e, st) {
        // Debug builds only: release builds log nothing about the account.
        if (kDebugMode) {
          debugPrint('Groups unavailable: $e');
          debugPrintStack(stackTrace: st);
        }
        groups = null;
      }
      scope.checkActive();
    }
    // 10. Return the session with cleanup and local-data removal.
    final session = AppSession(
      peerColors: peerColors,
      uid: user.uid,
      username: username,
      device: device,
      chat: chat,
      keys: keys,
      safety: safety,
      pushNotifications: pushNotifications,
      groups: groups,
      chatPreferences: chatPreferences,
      chatsSub: chatsSub,
      destroyLocalData: () async {
        await chatPreferences.close();
        await secrets.delete('chatprefskey:${user.uid}');
        await store.destroy(secrets, user.uid);
      },
      dispose: scope.cleanup,
    );
    scope.succeeded();
    return session;
  } finally {
    await scope.finish();
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
  // Refresh/error states may retain the previous, already-disposed session.
  // A resume must not close or invalidate that stale session again.
  final current = ref.watch(appSessionProvider);
  final session = current.isLoading ? null : current.asData?.value;
  final auth = ref.watch(authProvider);
  final secrets = ref.watch(secretStoreProvider);
  final preferences = ref.watch(accountPreferencesProvider);
  final credentials = ref.watch(iosPreviewCredentialsProvider);
  final erasureDirectories = ref.watch(accountErasureDirectoriesProvider);
  final uid = auth.currentUser?.uid;
  return AccountService(
    auth: auth,
    db: ref.watch(firestoreProvider),
    secrets: secrets,
    preferences: preferences,
    stopSession: session?.close,
    onMarked: () async {
      // Drop normal account access immediately after the confirmed fence.
      if (session != null) ref.invalidate(appSessionProvider);
      await credentials?.beforeLocalSignOut();
    },
    destroyLocalData: () async {
      if (uid == null) throw StateError('No account to erase.');
      // Resume does not initialize a chat session. Resolve the exact account
      // directories directly; never recreate/migrate history just to erase it.
      await eraseAccountHistory(
        uid: uid,
        roots: await erasureDirectories(),
        lockFor: (history) => accountLock(uid, history, generation: false),
      );
    },
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
