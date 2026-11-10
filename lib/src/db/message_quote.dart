class MessageQuote {
  const MessageQuote({
    required this.targetId,
    required this.senderUid,
    required this.body,
    this.unavailable = false,
  });
  final String targetId, senderUid, body;
  final bool unavailable;

  MessageQuote withoutContent() => MessageQuote(
    targetId: targetId,
    senderUid: senderUid,
    body: '',
    unavailable: true,
  );

  Map<String, dynamic> toJson() => {
    'targetId': targetId,
    'senderUid': senderUid,
    'body': body,
    if (unavailable) 'unavailable': true,
  };

  factory MessageQuote.fromJson(Map<String, dynamic> json) {
    final id = json['targetId'], uid = json['senderUid'], body = json['body'];
    if (id is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id) ||
        uid is! String ||
        uid.isEmpty ||
        uid.length > 128 ||
        body is! String ||
        body.length > 2048 ||
        body.runes.length > 1024 ||
        (json.containsKey('unavailable') && json['unavailable'] is! bool)) {
      throw const FormatException('Invalid quote');
    }
    return MessageQuote(
      targetId: id,
      senderUid: uid,
      body: body,
      unavailable: json['unavailable'] == true,
    );
  }
}
