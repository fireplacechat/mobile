import 'dart:math';

/// Person-to-person invites (app decision 0048, backend decision 0021).
///
/// Every account has invite rows that unlock some time after it was created.
/// The operator sets the schedule on the server; these defaults match the
/// rules when the operator has set nothing.
const defaultInviteUnlocks = [
  Duration.zero,
  Duration(days: 1),
  Duration(days: 7),
];

/// The rules accept row ids 0-9.
const maxInviteRows = 10;

/// After the first replacement, a row can be replaced once an hour.
const inviteReplaceWait = Duration(hours: 1);

const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

/// A new 16-character code (80 bits) in the sign-up format, without dashes.
String newInviteCode([Random? random]) {
  final r = random ?? Random.secure();
  return String.fromCharCodes(
    List.generate(16, (_) => _alphabet.codeUnitAt(r.nextInt(_alphabet.length))),
  );
}

/// `ABCDEFGHIJKLMNOP` -> `ABCD-EFGH-IJKL-MNOP`.
String formatInviteCode(String code) => [
  for (var i = 0; i < code.length; i += 4)
    code.substring(i, min(i + 4, code.length)),
].join('-');

/// The code this account made for one row.
class InviteSlot {
  const InviteSlot({
    required this.code,
    required this.invite,
    this.used = false,
    this.replacedAt,
    this.pending = false,
  });

  final String code;

  /// SHA-256 of [code]: the invite document id.
  final String invite;
  final bool used;
  final DateTime? replacedAt;

  /// Written on this phone but not yet confirmed by the server.
  final bool pending;
}

/// What the server says about this account's invites.
class InviteState {
  const InviteState({
    required this.createdAt,
    required this.unlockAfter,
    required this.paused,
    required this.slots,
  });

  final DateTime createdAt;
  final List<Duration> unlockAfter;
  final bool paused;
  final Map<int, InviteSlot> slots;

  /// One entry per row in the schedule, and one for any code made in a row the
  /// schedule no longer has.
  List<InviteRow> rowsAt(DateTime now) {
    final count = min(
      maxInviteRows,
      [unlockAfter.length, for (final i in slots.keys) i + 1].reduce(max),
    );
    return [
      for (var i = 0; i < count; i++)
        if (slots[i] case final slot?)
          CodeInvite(i, slot, replaceAfter: _replaceAfter(i, slot, now))
        else if (i < unlockAfter.length)
          if (now.isBefore(createdAt.add(unlockAfter[i])))
            LockedInvite(i, createdAt.add(unlockAfter[i]))
          else
            ReadyInvite(i, paused: paused),
    ];
  }

  /// When the code in row [i] may next be replaced, or null if it cannot be.
  DateTime? _replaceAfter(int i, InviteSlot slot, DateTime now) {
    if (slot.used || slot.pending || paused || i >= unlockAfter.length) {
      return null;
    }
    final last = slot.replacedAt;
    return last == null ? now : last.add(inviteReplaceWait);
  }
}

sealed class InviteRow {
  const InviteRow(this.index);

  /// 0-based; shown as 1-based.
  final int index;
}

/// The row unlocks at [readyAt].
final class LockedInvite extends InviteRow {
  const LockedInvite(super.index, this.readyAt);
  final DateTime readyAt;
}

/// A code can be made now, unless the operator has paused invites.
final class ReadyInvite extends InviteRow {
  const ReadyInvite(super.index, {required this.paused});
  final bool paused;
}

/// The row holds a code.
final class CodeInvite extends InviteRow {
  const CodeInvite(super.index, this.slot, {required this.replaceAfter});
  final InviteSlot slot;

  /// When the code may be replaced; null if it cannot be (used, paused, or a
  /// row the schedule no longer has).
  final DateTime? replaceAfter;

  bool canReplaceAt(DateTime now) =>
      replaceAfter != null && !now.isBefore(replaceAfter!);
}
