import 'package:fireplace/src/model/chat/chat_tuning.dart';

/// How a message writes the account's send clock `users/{uid}/limits/send`
/// (backend decision 0015, app decision 0028).
enum SendClock {
  /// Starts a window: `set({at, window, sent: 1})`.
  open,

  /// Counts one more in the current window: `update({at, sent: +1})`. Needs
  /// no read: the update keeps the window the server already holds.
  next,

  /// The older form `{at}` with a fixed gap, for a server that has not been
  /// updated to the window rule yet.
  legacy;

  /// The other window form, tried after the server refused this one.
  SendClock get other => this == open ? next : open;
}

/// Follows the server's send window on this device, so a send rarely waits
/// and rarely writes the clock in the wrong form. The server decides; when
/// this guesses wrong (another device opened a window, or the clocks differ)
/// the sender retries once the other way.
class SendAllowance {
  SendAllowance({DateTime Function()? clock}) : _now = clock ?? DateTime.now;
  final DateTime Function() _now;

  /// Room for the difference between this device's and the server's clock.
  static const margin = Duration(milliseconds: 500);

  DateTime? _opened;
  var _sent = 0;
  DateTime? _last;
  var _legacy = false;

  /// The form the next message should use.
  SendClock get next {
    if (_legacy) return SendClock.legacy;
    final opened = _opened;
    return opened != null &&
            _now().difference(opened) < ChatTuning.sendWindow - margin
        ? SendClock.next
        : SendClock.open;
  }

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
    final opened = _opened;
    if (next != SendClock.next || _sent < ChatTuning.sendBurst) {
      return Duration.zero;
    }
    return opened!.add(ChatTuning.sendWindow + margin).difference(now);
  }

  /// Records a message the server accepted with [clock]; [startedAt] is when
  /// its publish began, a little before the server's time for it.
  void published(SendClock clock, DateTime startedAt) {
    _last = _now();
    switch (clock) {
      case SendClock.open:
        _opened = startedAt;
        _sent = 1;
      case SendClock.next:
        // After another device opened the window this device does not know
        // when it started; the next send opens one and is corrected if not.
        _sent++;
      case SendClock.legacy:
        _legacy = true;
    }
  }
}
