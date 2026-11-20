import 'package:flutter/foundation.dart';

/// Someone waiting in Message requests: a person who wants to chat, or a
/// person who invited you to a group (whose name is hidden until you join).
@immutable
class WaitingRequest {
  const WaitingRequest(this.name, {this.group = false});
  final String name;
  final bool group;
}

/// The line under Message requests in the chat list (issue 248): who is
/// waiting, by username only. One: "fred wants to chat" or "fred invited you
/// to a group"; two or three: "fred and anna", "fred, anna and theo"; more:
/// "fred, anna and 2 others". Someone with two requests is named once.
String requestSummary(List<WaitingRequest> waiting) {
  if (waiting.isEmpty) return '';
  if (waiting.length == 1) {
    final only = waiting.single;
    return only.group
        ? '${only.name} invited you to a group'
        : '${only.name} wants to chat';
  }
  final names = {for (final w in waiting) w.name}.toList();
  if (names.length == 1) return '${names.single} is waiting';
  if (names.length <= 3) {
    return '${names.sublist(0, names.length - 1).join(', ')} '
        'and ${names.last}';
  }
  final others = names.length - 2;
  return '${names[0]}, ${names[1]} and $others '
      '${others == 1 ? 'other' : 'others'}';
}
