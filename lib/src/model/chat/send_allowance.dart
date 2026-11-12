import 'package:fireplace/src/model/chat/chat_tuning.dart';

/// How a message writes the account's send clock `users/{uid}/limits/send`
/// (backend decision 0015, app decision 0028). None of these needs a read:
/// an update keeps what the server already holds and adds one.
enum SendClock {
  /// Starts a day and a window: `set({at, window, sent: 1, day, today: 1})`.
  day,

  /// Starts a window in the running day:
  /// `update({at, window, sent: 1, today: +1})`.
  window,

  /// Counts one more in the running window and day:
  /// `update({at, sent: +1, today: +1})`.
  next,

  /// The older form `{at}` with a fixed gap, for a server that has not been
  /// updated to the window rule yet.
  legacy;

  /// The other window forms, in the order to try them after the server
  /// refused this one.
  List<SendClock> get others => switch (this) {
    day => const [window, next],
    window => const [day, next],
    next => const [window, day],
    legacy => const [],
  };
}

/// Follows the server's send window and day on this device, so a send rarely
/// waits and rarely writes the clock in the wrong form. The server decides;
/// when this guesses wrong (another device opened a window or day, or the
/// clocks differ) the sender tries the other forms.
class SendAllowance {
  SendAllowance({DateTime Function()? clock}) : _now = clock ?? DateTime.now;
  final DateTime Function() _now;

  /// Room for the difference between this device's and the server's clock.
  static const margin = Duration(milliseconds: 500);
  static const dayMargin = Duration(minutes: 1);

  DateTime? _windowOpened;
  var _sent = 0;
  DateTime? _dayOpened;
  var _today = 0;
  DateTime? _last;
  var _legacy = false;

  bool get _windowRuns {
    final opened = _windowOpened;
    return opened != null &&
        _now().difference(opened) < ChatTuning.sendWindow - margin;
  }

  bool get _dayRuns {
    final opened = _dayOpened;
    return opened != null &&
        _now().difference(opened) < ChatTuning.sendDay - dayMargin;
  }

  /// The form the next message should use.
  SendClock get next {
    if (_legacy) return SendClock.legacy;
    if (_windowRuns) return SendClock.next;
    return _dayRuns ? SendClock.window : SendClock.day;
  }

  /// This device alone has sent the day's cap. The server may refuse sooner,
  /// when the account's other devices sent too; it is the one that decides.
  bool get capReached =>
      !_legacy && _dayRuns && _today >= ChatTuning.sendDailyCap;

  /// When this device's day ends, once [capReached].
  DateTime? get dayEnds => _dayOpened?.add(ChatTuning.sendDay);

  /// How long the next message has to wait so the server accepts it: until
  /// the window ends once its burst is used up, or the older gap.
  Duration get wait {
    if (!ChatTuning.pacing) return Duration.zero;
    final now = _now();
    if (_legacy) {
      final last = _last;
      return last == null
          ? Duration.zero
          : ChatTuning.legacySendGap - now.difference(last);
    }
    if (!_windowRuns || _sent < ChatTuning.sendBurst) return Duration.zero;
    return _windowOpened!.add(ChatTuning.sendWindow + margin).difference(now);
  }

  /// Records a message the server accepted with [clock]; [startedAt] is when
  /// its publish began, a little before the server's time for it.
  void published(SendClock clock, DateTime startedAt) {
    _last = _now();
    switch (clock) {
      case SendClock.day:
        _dayOpened = startedAt;
        _today = 1;
        _windowOpened = startedAt;
        _sent = 1;
      case SendClock.window:
        // Another device may have opened the day: it runs, but when it began
        // is unknown. Guessing now is corrected by the server if wrong.
        _dayOpened ??= startedAt;
        _today++;
        _windowOpened = startedAt;
        _sent = 1;
      case SendClock.next:
        _dayOpened ??= startedAt;
        _windowOpened ??= startedAt;
        _today++;
        _sent++;
      case SendClock.legacy:
        _legacy = true;
    }
  }
}
