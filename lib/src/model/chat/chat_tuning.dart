class ChatTuning {
  static const requestLimit = 3;

  /// A session we started that the peer never answered for this long is considered
  /// possibly lost (for example the peer lost the matching prekey), so the next send
  /// starts a fresh handshake as well. Old sessions stay, so late replies still work.
  static Duration staleSessionAfter = const Duration(hours: 24);
  static const pruneAfter = Duration(days: 30);

  /// Minimum time between two sends from this device. The server enforces 500 ms
  /// per account across all chats; this stays safely above it so honest use never
  /// trips the rule. Tests set it to zero (test/flutter_test_config.dart).
  static Duration sendGap = const Duration(milliseconds: 700);
  static const pageCap = 500;
}
