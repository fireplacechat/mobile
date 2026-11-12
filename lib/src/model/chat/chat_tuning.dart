class ChatTuning {
  static const requestLimit = 3;

  /// A session we started that the peer never answered for this long is considered
  /// possibly lost (for example the peer lost the matching prekey), so the next send
  /// starts a fresh handshake as well. Old sessions stay, so late replies still work.
  static Duration staleSessionAfter = const Duration(hours: 24);
  static const pruneAfter = Duration(days: 30);

  /// The server's send limits (backend decision 0015), per account across
  /// all chats: up to [sendBurst] messages per [sendWindow].
  static Duration sendWindow = const Duration(seconds: 10);
  static int sendBurst = 20;

  /// And at most [sendDailyCap] messages, reactions included, in a day of
  /// [sendDay] from the first one.
  static Duration sendDay = const Duration(days: 1);
  static int sendDailyCap = 2000;

  /// Off in tests (test/flutter_test_config.dart), which have no server
  /// rules: sends never wait, and a refused send clock is not retried.
  static bool pacing = true;

  /// After every form of the send clock was refused, the pauses before
  /// trying them all again (decision 0032). A refusal that nothing was
  /// committed for is safe to retry; most clear within a second (a window
  /// that ended mid-attempt, a sign-in token being refreshed).
  static List<Duration> refusalRetries = const [
    Duration(milliseconds: 300),
    Duration(seconds: 1),
  ];
  static const pageCap = 500;
}
