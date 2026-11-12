import 'package:fireplace/src/view/chat/widgets/day_separator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('two times on the same local day, hours apart', () {
    expect(
      sameLocalDay(DateTime(2026, 6, 15, 1, 5), DateTime(2026, 6, 15, 22, 40)),
      isTrue,
    );
  });

  test('23:59 and 00:00 the next day are different days', () {
    expect(
      sameLocalDay(DateTime(2026, 1, 1, 23, 59), DateTime(2026, 1, 2, 0, 0)),
      isFalse,
    );
  });

  test('the same day number in another month or year is a different day', () {
    expect(
      sameLocalDay(DateTime(2026, 1, 15, 12), DateTime(2026, 2, 15, 12)),
      isFalse,
    );
    expect(
      sameLocalDay(DateTime(2026, 3, 1, 8), DateTime(2025, 3, 1, 8)),
      isFalse,
    );
  });

  test('the same instant as UTC and as local is the same day', () {
    final local = DateTime(2026, 1, 1, 23, 59);
    expect(sameLocalDay(local, local.toUtc()), isTrue);
  });
}
