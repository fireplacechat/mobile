import 'dart:math';

import 'package:fireplace/src/model/account/auth_service.dart';
import 'package:fireplace/src/model/invites/invite_rows.dart';
import 'package:flutter_test/flutter_test.dart';

final t0 = DateTime.utc(2026, 11, 14, 12);

InviteState state({
  List<Duration> unlockAfter = defaultInviteUnlocks,
  bool paused = false,
  Map<int, InviteSlot> slots = const {},
}) => InviteState(
  createdAt: t0,
  unlockAfter: unlockAfter,
  paused: paused,
  slots: slots,
);

const slot = InviteSlot(code: 'ABCDEFGHIJKLMNOP', invite: 'h');

void main() {
  test(
    'row 1 is ready at once; rows 2 and 3 count down to a day and a week',
    () {
      final rows = state().rowsAt(t0);
      expect(rows, hasLength(3));
      expect(rows[0], isA<ReadyInvite>());
      expect(
        (rows[1] as LockedInvite).readyAt,
        t0.add(const Duration(days: 1)),
      );
      expect(
        (rows[2] as LockedInvite).readyAt,
        t0.add(const Duration(days: 7)),
      );

      final later = state().rowsAt(t0.add(const Duration(days: 1)));
      expect(later[1], isA<ReadyInvite>());
      expect(later[2], isA<LockedInvite>());
      expect(
        state().rowsAt(t0.add(const Duration(days: 7))),
        everyElement(isA<ReadyInvite>()),
      );
    },
  );

  test('a row with a code can be replaced at once, then once an hour', () {
    final now = t0.add(const Duration(days: 2));
    final fresh = state(slots: {0: slot}).rowsAt(now)[0] as CodeInvite;
    expect(fresh.canReplaceAt(now), isTrue);

    final swapped = InviteSlot(
      code: slot.code,
      invite: 'h',
      replacedAt: now.subtract(const Duration(minutes: 10)),
    );
    final row = state(slots: {0: swapped}).rowsAt(now)[0] as CodeInvite;
    expect(row.canReplaceAt(now), isFalse);
    expect(row.canReplaceAt(now.add(const Duration(minutes: 50))), isTrue);
  });

  test('used, unconfirmed and paused codes cannot be replaced', () {
    for (final s in [
      const InviteSlot(code: 'ABCDEFGHIJKLMNOP', invite: 'h', used: true),
      const InviteSlot(code: 'ABCDEFGHIJKLMNOP', invite: 'h', pending: true),
    ]) {
      final row = state(slots: {0: s}).rowsAt(t0)[0] as CodeInvite;
      expect(row.replaceAfter, isNull);
    }
    final paused = state(paused: true, slots: {0: slot}).rowsAt(t0);
    expect((paused[0] as CodeInvite).replaceAfter, isNull);
  });

  test('pausing keeps the rows but marks ready ones paused', () {
    final rows = state(paused: true).rowsAt(t0.add(const Duration(days: 8)));
    expect(rows, hasLength(3));
    expect(rows.cast<ReadyInvite>().every((r) => r.paused), isTrue);
  });

  test('the operator schedule sets the number of rows', () {
    expect(state(unlockAfter: const []).rowsAt(t0), isEmpty);
    final five = state(unlockAfter: List.filled(5, Duration.zero)).rowsAt(t0);
    expect(five, hasLength(5));
    expect(five, everyElement(isA<ReadyInvite>()));
  });

  test('a code in a row the schedule no longer has is still shown', () {
    final rows = state(
      unlockAfter: const [Duration.zero],
      slots: {2: slot},
    ).rowsAt(t0);
    expect(rows.map((r) => r.index), [0, 2]);
    expect((rows[1] as CodeInvite).replaceAfter, isNull);
  });

  test('new codes use the sign-up format and look random', () {
    final r = Random(7);
    final codes = {for (var i = 0; i < 200; i++) newInviteCode(r)};
    expect(codes, hasLength(200));
    for (final c in codes) {
      expect(c, matches(RegExp(r'^[A-Z2-7]{16}$')));
      expect(AuthService.normalizeInvite(formatInviteCode(c)), c);
    }
    expect(formatInviteCode('ABCDEFGHIJKLMNOP'), 'ABCD-EFGH-IJKL-MNOP');
  });
}
