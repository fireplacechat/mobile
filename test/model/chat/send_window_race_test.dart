// "Not sent" for messages an immediate "Send again" delivered (decision 0032).
//
// The rules accept exactly one send-clock form at a time (backend decision
// 0015). Near the end of a 10-second window the app guessed "new window" a
// little early, was refused, spent a round trip on "new day" (always refused
// within a day) and tried "next" last, after the window had ended: every form
// refused. This drives the app's own publishWithClock and SendAllowance
// against a model of those rules, with a fake clock and mobile round trips.
import 'dart:math';

import 'package:fireplace/src/model/chat/chat_tuning.dart';
import 'package:fireplace/src/model/chat/send_allowance.dart';
import 'package:flutter_test/flutter_test.dart';

class _Refused implements Exception {}

/// `users/{uid}/limits/send` and its rules.
class _Server {
  DateTime? window, day;
  int sent = 0, today = 0;

  bool accept(SendClock form, DateTime t) {
    final dayRuns = day != null && t.isBefore(day!.add(ChatTuning.sendDay));
    final windowRuns =
        window != null && t.isBefore(window!.add(ChatTuning.sendWindow));
    switch (form) {
      case SendClock.day:
        if (dayRuns || windowRuns) return false;
        day = window = t;
        today = sent = 1;
      case SendClock.window:
        if (!dayRuns || windowRuns || today >= ChatTuning.sendDailyCap) {
          return false;
        }
        window = t;
        sent = 1;
        today++;
      case SendClock.next:
        if (!dayRuns || !windowRuns || sent >= ChatTuning.sendBurst) {
          return false;
        }
        if (today >= ChatTuning.sendDailyCap) return false;
        sent++;
        today++;
      case SendClock.dayInWindow:
        if (dayRuns || !windowRuns || sent >= ChatTuning.sendBurst) {
          return false;
        }
        day = t;
        today = 1;
        sent++;
    }
    return true;
  }
}

class _World {
  _World(int seed) : rnd = Random(seed);
  final Random rnd;
  var now = DateTime.utc(2026, 11, 12);
  final server = _Server();

  /// A mobile round trip: 50 ms to 1.5 s, different every time.
  Duration rtt() => Duration(milliseconds: 50 + rnd.nextInt(1450));

  Future<void> publish(SendClock form) async {
    final trip = rtt();
    final arrives = now.add(trip ~/ 2);
    now = now.add(trip);
    if (!server.accept(form, arrives)) throw _Refused();
  }
}

/// Sends [count] messages from [devices] devices of one account, with gaps
/// drawn from [gap]. Returns how many were refused in the end.
Future<int> _run({
  required int seed,
  required int count,
  int devices = 1,
  required Duration Function(Random rnd) gap,
  List<SendClock> Function(SendClock guess)? oldOrder,
}) async {
  final world = _World(seed);
  final allowances = [
    for (var i = 0; i < devices; i++) SendAllowance(clock: () => world.now),
  ];
  var failed = 0;
  for (var i = 0; i < count; i++) {
    world.now = world.now.add(gap(world.rnd));
    final allowance = allowances[world.rnd.nextInt(devices)];
    world.now = world.now.add(allowance.wait);
    if (oldOrder != null) {
      // The order before decision 0032, for comparison.
      final start = world.now;
      var ok = false;
      for (final form in oldOrder(allowance.next)) {
        try {
          await world.publish(form);
          allowance.published(form, start);
          ok = true;
          break;
        } on _Refused {
          continue;
        }
      }
      if (!ok) failed++;
      continue;
    }
    try {
      await publishWithClock(
        allowance: allowance,
        publish: world.publish,
        retryable: (e) => e is _Refused,
        pauses: ChatTuning.refusalRetries,
        sleep: (d) async => world.now = world.now.add(d),
        now: () => world.now,
      );
    } on _Refused {
      failed++;
    }
  }
  return failed;
}

/// Bursts of quick messages and reactions, with pauses between them.
Duration _chatting(Random rnd) => rnd.nextInt(6) == 0
    ? Duration(seconds: 5 + rnd.nextInt(60))
    : Duration(milliseconds: rnd.nextInt(4000));

void main() {
  setUp(() {
    ChatTuning.pacing = true;
    // Days of real chatting here pass the real cap; that refusal is meant.
    ChatTuning.sendDailyCap = 1 << 30;
  });
  tearDown(() {
    ChatTuning.pacing = false;
    ChatTuning.sendDay = const Duration(days: 1);
    ChatTuning.sendDailyCap = 2000;
  });

  test('the model shows the old failure', () async {
    List<SendClock> old(SendClock guess) => switch (guess) {
      SendClock.day => [SendClock.day, SendClock.window, SendClock.next],
      SendClock.window => [SendClock.window, SendClock.day, SendClock.next],
      _ => [SendClock.next, SendClock.window, SendClock.day],
    };
    final failed = await _run(
      seed: 1,
      count: 20000,
      gap: _chatting,
      oldOrder: old,
    );
    expect(failed, greaterThan(100), reason: 'the race this test guards');
  });

  test('one device chatting: no send is refused', () async {
    for (var seed = 1; seed <= 5; seed++) {
      expect(await _run(seed: seed, count: 40000, gap: _chatting), 0);
    }
  });

  test('two devices of one account: no send is refused', () async {
    for (var seed = 1; seed <= 5; seed++) {
      expect(
        await _run(seed: seed, count: 40000, devices: 2, gap: _chatting),
        0,
      );
    }
  });

  test('days ending inside a window: no send is refused', () async {
    // A one-minute "day", so its end falls inside windows thousands of times.
    ChatTuning.sendDay = const Duration(minutes: 1);
    for (var seed = 1; seed <= 5; seed++) {
      expect(await _run(seed: seed, count: 40000, gap: _chatting), 0);
      expect(
        await _run(seed: seed, count: 40000, devices: 2, gap: _chatting),
        0,
      );
    }
  });

  test('faster than the burst allows: sends wait, none is refused', () async {
    expect(
      await _run(
        seed: 7,
        count: 20000,
        gap: (rnd) => Duration(milliseconds: rnd.nextInt(200)),
      ),
      0,
    );
  });
}
