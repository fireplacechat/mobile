class ChatTuning {
  static const requestLimit = 3;

  /// A session we started that the peer never answered for this long is considered
  /// possibly lost (for example the peer lost the matching prekey), so the next send
  /// starts a fresh handshake as well. Old sessions stay, so late replies still work.
  static Duration staleSessionAfter = const Duration(hours: 24);
  static const pruneAfter = Duration(days: 30);

  /// The server's send window (backend decision 0015): up to [sendBurst]
  /// messages per [sendWindow] per account, across all chats.
  static Duration sendWindow = const Duration(seconds: 10);
  static int sendBurst = 20;

  /// The gap a server still on the older rule (500 ms per account) needs,
  /// with a margin so honest use never trips it.
  static Duration legacySendGap = const Duration(milliseconds: 700);

  /// Off in tests (test/flutter_test_config.dart), which have no server
  /// rules: sends never wait, and a refused send clock is not retried.
  static bool pacing = true;
  static const pageCap = 500;
}
