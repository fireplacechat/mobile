import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fireplace/src/app/providers.dart';
import 'package:fireplace/src/model/invites/invite_rows.dart';
import 'package:fireplace/src/model/invites/invite_service.dart';

final inviteServiceProvider = Provider<InviteService>(
  (ref) => InviteService(ref.watch(firestoreProvider)),
);

/// This account's invites, live while the Invite page is open. Watches the
/// signed-in uid, so it resets on sign-out.
final inviteStateProvider = StreamProvider.autoDispose<InviteState?>((ref) {
  final uid = ref.watch(appSessionProvider.select((s) => s.value?.uid));
  if (uid == null) return Stream.value(null);
  return ref.watch(inviteServiceProvider).watch(uid);
});

/// The time used for countdowns; tests replace it.
final inviteClockProvider = Provider<DateTime Function()>((_) => DateTime.now);
