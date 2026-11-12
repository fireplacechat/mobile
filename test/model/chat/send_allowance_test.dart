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

  test('a new window opens once the last one is nearly over', () {
    send();
    now = now.add(ChatTuning.sendWindow - SendAllowance.margin);
    expect(allowance.next, SendClock.window);
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

  test('on a server still on the older rule, the older gap applies', () {
    allowance.published(SendClock.legacy, now);
    expect(allowance.next, SendClock.legacy);
    expect(allowance.capReached, isFalse);
    now = now.add(const Duration(milliseconds: 200));
    expect(
      allowance.wait,
      ChatTuning.legacySendGap - const Duration(milliseconds: 200),
    );
  });

  test('tests without pacing never wait', () {
    for (var i = 0; i < ChatTuning.sendBurst; i++) {
      send();
    }
    ChatTuning.pacing = false;
    expect(allowance.wait, Duration.zero);
  });

  test('after a refusal the other forms are tried, the likeliest first', () {
    expect(SendClock.day.others, [SendClock.window, SendClock.next]);
    expect(SendClock.window.others, [SendClock.day, SendClock.next]);
    expect(SendClock.next.others, [SendClock.window, SendClock.day]);
    expect(SendClock.legacy.others, isEmpty);
  });
}
