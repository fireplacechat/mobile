import 'package:fireplace/src/model/chat/chat_tuning.dart';
import 'package:fireplace/src/model/chat/send_allowance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime now;
  late SendAllowance allowance;
  setUp(() {
    ChatTuning.pacing = true;
    now = DateTime(2026, 11, 12, 12);
    allowance = SendAllowance(clock: () => now);
  });
  tearDown(() {
    ChatTuning.pacing = false;
    ChatTuning.sendDailyCap = 2000;
  });

  void send() {
    final clock = allowance.next;
    allowance.published(clock, now);
  }

  test('the first message opens a day; the next ones count in it', () {
    expect(allowance.next, SendClock.day);
    send();
    now = now.add(const Duration(seconds: 3));
    expect(allowance.next, SendClock.next);
    expect(allowance.wait, Duration.zero);
  });

  test('a new window is guessed only once the last one is over', () {
    // Guessing it early was refused near the end of every window.
    send();
    now = now.add(ChatTuning.sendWindow - const Duration(milliseconds: 1));
    expect(allowance.next, SendClock.next);
    now = now.add(const Duration(milliseconds: 1));
    expect(allowance.next, SendClock.window);
  });

  test('a day that ends inside a window is opened without a new window', () {
    send();
    now = now.add(
      ChatTuning.sendDay - SendAllowance.dayMargin - const Duration(seconds: 5),
    );
    send(); // opens a window
    now = now.add(const Duration(seconds: 6));
    expect(allowance.next, SendClock.dayInWindow);
    send();
    expect(allowance.next, SendClock.next);
    expect(allowance.capReached, isFalse);
  });

  test('the wait for a used-up burst counts from the server answer', () {
    final start = now;
    for (var i = 0; i < ChatTuning.sendBurst; i++) {
      allowance.published(
        allowance.next,
        start,
        start.add(const Duration(seconds: 1)),
      );
    }
    expect(
      allowance.wait,
      ChatTuning.sendWindow + SendAllowance.margin + const Duration(seconds: 1),
    );
  });

  test('a new day opens once the last one is nearly over', () {
    send();
    now = now.add(ChatTuning.sendDay - SendAllowance.dayMargin);
    expect(allowance.next, SendClock.day);
  });

  test('a used-up burst waits for the end of its window, with a margin', () {
    for (var i = 0; i < ChatTuning.sendBurst; i++) {
      send();
    }
    now = now.add(const Duration(seconds: 2));
    expect(allowance.next, SendClock.next);
    expect(
      allowance.wait,
      ChatTuning.sendWindow + SendAllowance.margin - const Duration(seconds: 2),
    );
  });

  test('the daily cap is reached on this device alone, and lifts next day', () {
    ChatTuning.sendDailyCap = 3;
    for (var i = 0; i < 3; i++) {
      send();
      now = now.add(const Duration(minutes: 1));
    }
    expect(allowance.capReached, isTrue);
    expect(allowance.dayEnds, DateTime(2026, 11, 13, 12));
    now = now.add(ChatTuning.sendDay);
    expect(allowance.capReached, isFalse);
    expect(allowance.next, SendClock.day);
  });

  test('a day another device opened is assumed to run', () {
    allowance.published(SendClock.window, now);
    now = now.add(const Duration(seconds: 20));
    expect(allowance.next, SendClock.window);
  });

  test('tests without pacing never wait', () {
    for (var i = 0; i < ChatTuning.sendBurst; i++) {
      send();
    }
    ChatTuning.pacing = false;
    expect(allowance.wait, Duration.zero);
  });

  test('every form is tried, the other window state right after', () {
    expect(SendClock.next.tryOrder, [
      SendClock.next,
      SendClock.window,
      SendClock.dayInWindow,
      SendClock.day,
    ]);
    expect(SendClock.window.tryOrder, [
      SendClock.window,
      SendClock.next,
      SendClock.day,
      SendClock.dayInWindow,
    ]);
    expect(SendClock.day.tryOrder, [
      SendClock.day,
      SendClock.dayInWindow,
      SendClock.window,
      SendClock.next,
    ]);
    expect(SendClock.dayInWindow.tryOrder, [
      SendClock.dayInWindow,
      SendClock.day,
      SendClock.next,
      SendClock.window,
    ]);
  });
}
