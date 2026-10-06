class ChatSummary {
  ChatSummary(
    this.chatId,
    this.peerUid,
    this.lastMessageAt, {
    this.initiator,
    this.accepted = true,
    this.requestCount = 0,
  });
  final String chatId;
  final String peerUid;
  final DateTime? lastMessageAt;

  /// Who started the chat. Null for chats created before message requests existed.
  final String? initiator;

  /// False while the chat is a message request awaiting the recipient.
  final bool accepted;
  final int requestCount;

  /// A request somebody else sent me that I have not accepted yet.
  bool isIncomingRequest(String me) =>
      !accepted && initiator != null && initiator != me;
}
