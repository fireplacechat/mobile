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
  tearDown(() => ChatTuning.pacing = false);

  void send() {
    final clock = allowance.next;
    allowance.published(clock, now);
  }

  test('the first message opens a window; the next ones count in it', () {
    expect(allowance.next, SendClock.open);
    send();
    now = now.add(const Duration(seconds: 3));
    expect(allowance.next, SendClock.next);
    expect(allowance.wait, Duration.zero);
  });

  test('a new window opens once the last one is nearly over', () {
    send();
    now = now.add(ChatTuning.sendWindow - SendAllowance.margin);
    expect(allowance.next, SendClock.open);
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

  test('on a server still on the older rule, the older gap applies', () {
    allowance.published(SendClock.legacy, now);
    expect(allowance.next, SendClock.legacy);
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

  test('the other form of a window clock', () {
    expect(SendClock.open.other, SendClock.next);
    expect(SendClock.next.other, SendClock.open);
  });
}
