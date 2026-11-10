/// One winning revision slot. Ties from linked devices have a stable ordering.
class MessageEdit {
  const MessageEdit({
    required this.revision,
    required this.body,
    required this.deviceId,
    required this.eventId,
    required this.sentAt,
  });
  final int revision;
  final String body, deviceId, eventId;
  final DateTime sentAt;
  bool newerThan(MessageEdit other) {
    final device = deviceId.compareTo(other.deviceId);
    return device != 0 ? device > 0 : eventId.compareTo(other.eventId) > 0;
  }

  Map<String, dynamic> toJson() => {
    'revision': revision,
    'body': body,
    'deviceId': deviceId,
    'eventId': eventId,
    'sentAt': sentAt.millisecondsSinceEpoch,
  };
  factory MessageEdit.fromJson(Map<String, dynamic> j) => MessageEdit(
    revision: j['revision'],
    body: j['body'],
    deviceId: j['deviceId'],
    eventId: j['eventId'],
    sentAt: DateTime.fromMillisecondsSinceEpoch(j['sentAt']),
  );
}
