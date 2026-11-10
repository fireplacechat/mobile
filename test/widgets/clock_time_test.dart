import 'package:fireplace/src/widgets/clock_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const localizations = DefaultMaterialLocalizations();
  test('times of day are written with a lower-case period', () {
    expect(clockTime(DateTime(2026, 10, 4, 9, 5), localizations), '9:05 am');
    expect(clockTime(DateTime(2026, 10, 4, 15, 3), localizations), '3:03 pm');
    expect(clockTime(DateTime(2026, 10, 4, 0, 0), localizations), '12:00 am');
    expect(clockTime(DateTime(2026, 10, 4, 12, 0), localizations), '12:00 pm');
  });

  test('a time stored in UTC is shown in local time', () {
    final utc = DateTime.utc(2026, 10, 4, 9, 5);
    expect(
      clockTime(utc, localizations),
      clockTime(utc.toLocal(), localizations),
    );
  });
}
