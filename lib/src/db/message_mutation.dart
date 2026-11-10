enum MessageMutationKind { reaction, delete }

enum ReactionOperation { set, clear }

class MessageMutation {
  const MessageMutation({
    required this.kind,
    required this.targetId,
    this.emoji = '',
    this.operation = ReactionOperation.set,
    this.revision = 0,
  });
  final MessageMutationKind kind;
  final String targetId, emoji;
  final ReactionOperation operation;
  final int revision;

  Map<String, dynamic> toJson() => {
    'type': kind.name,
    'targetId': targetId,
    if (kind == MessageMutationKind.reaction) ...{
      'emoji': emoji,
      'operation': operation.name,
      'revision': revision,
    },
  };

  factory MessageMutation.fromJson(Map<String, dynamic> j) {
    final kind = MessageMutationKind.values.byName(j['type'] as String);
    final target = j['targetId'];
    if (target is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(target)) {
      throw const FormatException('Invalid target');
    }
    if (kind == MessageMutationKind.delete) {
      return MessageMutation(kind: kind, targetId: target);
    }
    final emoji = j['emoji'], revision = j['revision'];
    if (emoji is! String ||
        !validReactionEmoji(emoji) ||
        revision is! int ||
        revision < 1 ||
        revision > 9007199254740991) {
      throw const FormatException('Invalid reaction');
    }
    return MessageMutation(
      kind: kind,
      targetId: target,
      emoji: emoji,
      operation: ReactionOperation.values.byName(j['operation'] as String),
      revision: revision,
    );
  }
}

// Bounded Unicode emoji sequences: pictographs, modifiers, joins, flags and keycaps.
// No package or platform emoji keyboard is needed to validate encrypted content.
bool validReactionEmoji(String value) {
  if (value.isEmpty || value.length > 64) return false;
  return _emoji.hasMatch(value);
}

const _pictograph =
    r'[\u{1F300}-\u{1F3FA}\u{1F400}-\u{1FAFF}\u2600-\u27BF'
    r'\u00A9\u00AE\u203C\u2049\u2122\u2139\u2194-\u21FF\u2300-\u23FF'
    r'\u2B00-\u2BFF\u3030\u303D\u3297\u3299]';
final _emoji = RegExp(
  '^(?:$_pictograph'
  r'\uFE0F?[\u{1F3FB}-\u{1F3FF}]?'
  '(?:\u200D$_pictograph'
  r'\uFE0F?[\u{1F3FB}-\u{1F3FF}]?)*'
  r'|[\u{1F1E6}-\u{1F1FF}]{2}|[0-9#*]\uFE0F?\u20E3)$',
  unicode: true,
);

class MessageReaction {
  const MessageReaction({
    required this.emoji,
    required this.revision,
    required this.deviceId,
    required this.eventId,
  });
  final String? emoji;
  final int revision;
  final String deviceId, eventId;
  bool newerThan(MessageReaction other) {
    final byRevision = revision.compareTo(other.revision);
    if (byRevision != 0) return byRevision > 0;
    final byDevice = deviceId.compareTo(other.deviceId);
    return byDevice != 0 ? byDevice > 0 : eventId.compareTo(other.eventId) > 0;
  }

  Map<String, dynamic> toJson() => {
    'emoji': emoji,
    'revision': revision,
    'deviceId': deviceId,
    'eventId': eventId,
  };
  factory MessageReaction.fromJson(Map<String, dynamic> j) => MessageReaction(
    emoji: j['emoji'],
    revision: j['revision'],
    deviceId: j['deviceId'],
    eventId: j['eventId'],
  );
}
