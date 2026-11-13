import 'package:fireplace/src/model/chat/chat_tuning.dart';

/// How a message writes the account's send clock `users/{uid}/limits/send`
/// (backend decision 0015, app decisions 0028 and 0032). None of these needs
/// a read: an update keeps what the server already holds and adds one.
///
/// The server's clock is in one of four states, and the rules accept exactly
/// one form in each: whether the day of 24 hours runs, and whether the window
/// of 10 seconds runs.
enum SendClock {
  /// No day and no window run: `set({at, window, sent: 1, day, today: 1})`.
  day,

  /// The day runs, the window is over:
  /// `update({at, window, sent: 1, today: +1})`.
  window,

  /// Both run: `update({at, sent: +1, today: +1})`.
  next,

  /// The day is over while a window still runs:
  /// `update({at, day, today: 1, sent: +1})`. Without it every other form is
  /// refused until that window ends.
  dayInWindow;

  bool get _dayRuns => this == window || this == next;
  bool get _windowRuns => this == next || this == dayInWindow;

  static SendClock _of({required bool dayRuns, required bool windowRuns}) =>
      dayRuns ? (windowRuns ? next : window) : (windowRuns ? dayInWindow : day);

  /// Every form, this one first, then the likeliest after it is refused:
  /// the other window state (a window ends or starts every few seconds and
  /// the clocks differ a little), then the other day state, then both.
  List<SendClock> get tryOrder => [
    this,
    _of(dayRuns: _dayRuns, windowRuns: !_windowRuns),
    _of(dayRuns: !_dayRuns, windowRuns: _windowRuns),
    _of(dayRuns: !_dayRuns, windowRuns: !_windowRuns),
  ];
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

  /// When the publish that opened the window started and when the server
  /// answered: the server's time for it lies between the two.
  DateTime? _windowOpened, _windowConfirmed;
  var _sent = 0;
  DateTime? _dayOpened;
  var _today = 0;

  bool get _windowRuns {
    final opened = _windowOpened;
    return opened != null && _now().difference(opened) < ChatTuning.sendWindow;
  }

  bool get _dayRuns {
    final opened = _dayOpened;
    return opened != null &&
        _now().difference(opened) < ChatTuning.sendDay - dayMargin;
  }

  /// The form the next message should try first.
  SendClock get next =>
      SendClock._of(dayRuns: _dayRuns, windowRuns: _windowRuns);

  /// This device alone has sent the day's cap. The server may refuse sooner,
  /// when the account's other devices sent too; it is the one that decides.
  bool get capReached => _dayRuns && _today >= ChatTuning.sendDailyCap;

  /// When this device's day ends, once [capReached].
  DateTime? get dayEnds => _dayOpened?.add(ChatTuning.sendDay);

  /// How long the next message has to wait so the server accepts it: until
  /// the window ends, once its burst is used up. Counted from when the server
  /// confirmed the window, the latest it can have opened, so the wait is not
  /// cut short.
  Duration get wait {
    if (!ChatTuning.pacing) return Duration.zero;
    if (!_windowRuns || _sent < ChatTuning.sendBurst) return Duration.zero;
    final opened = _windowConfirmed ?? _windowOpened!;
    final left = opened.add(ChatTuning.sendWindow + margin).difference(_now());
    return left.isNegative ? Duration.zero : left;
  }

  /// Records a message the server accepted with [clock]; [startedAt] is when
  /// its publish began and [confirmedAt] when the server answered.
  void published(SendClock clock, DateTime startedAt, [DateTime? confirmedAt]) {
    final confirmed = confirmedAt ?? startedAt;
    void openWindow() {
      _windowOpened = startedAt;
      _windowConfirmed = confirmed;
      _sent = 1;
    }

    void countInWindow() {
      if (_windowOpened == null) {
        // Another device opened it; when is unknown. Guessing now is
        // corrected by the server if wrong.
        _windowOpened = startedAt;
        _windowConfirmed = confirmed;
      }
      _sent++;
    }

    switch (clock) {
      case SendClock.day:
        _dayOpened = startedAt;
        _today = 1;
        openWindow();
      case SendClock.window:
        _dayOpened ??= startedAt;
        _today++;
        openWindow();
      case SendClock.next:
        _dayOpened ??= startedAt;
        _today++;
        countInWindow();
      case SendClock.dayInWindow:
        _dayOpened = startedAt;
        _today = 1;
        countInWindow();
    }
  }
}

/// Publishes a message with the first send-clock form the server accepts
/// (decision 0032). Each round tries every form, likeliest first; when all
/// are refused it waits for the next of [pauses] and tries again, since the
/// server's state changes with time (a window or day ends) and with the
/// account's other devices. Only [retryable] errors are tried again: they
/// mean nothing was committed. Anything else is passed on at once. After the
/// last round the last refusal is passed on.
Future<void> publishWithClock({
  required SendAllowance allowance,
  required Future<void> Function(SendClock clock) publish,
  required bool Function(Object error) retryable,
  required List<Duration> pauses,
  Future<void> Function(Duration pause)? sleep,
  DateTime Function()? now,
}) async {
  final pause = sleep ?? (d) => Future<void>.delayed(d);
  final time = now ?? DateTime.now;
  Object? last;
  StackTrace? lastStack;
  for (var round = 0; round <= pauses.length; round++) {
    if (round > 0) await pause(pauses[round - 1]);
    for (final clock in allowance.next.tryOrder) {
      final startedAt = time();
      try {
        await publish(clock);
        allowance.published(clock, startedAt, time());
        return;
      } catch (e, st) {
        if (!retryable(e)) rethrow;
        last = e;
        lastStack = st;
      }
    }
  }
  Error.throwWithStackTrace(last!, lastStack!);
}
