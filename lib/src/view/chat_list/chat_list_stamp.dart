import 'package:flutter/material.dart';
import 'package:fireplace/src/widgets/clock_time.dart';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// The short label beside a conversation: a lower-case time today, a weekday within the
/// last week, otherwise a numeric date (with the year only when it differs).
String chatListStamp(
  DateTime sentAt,
  DateTime now,
  MaterialLocalizations localizations,
) {
  final at = sentAt.toLocal();
  final today = now.toLocal();
  final days = DateUtils.dateOnly(today)
      .difference(DateUtils.dateOnly(at))
      .inDays;
  if (days <= 0) {
    return clockTime(at, localizations);
  }
  if (days < 7) return _weekdays[at.weekday - 1];
  final date = localizations.formatCompactDate(at);
  if (at.year != today.year) return date;
  // Drop the year and the separator beside it, keeping the locale's order.
  return date.replaceFirst(RegExp(r'(^\d{4}\D)|(\D\d{4}$)'), '');
}
