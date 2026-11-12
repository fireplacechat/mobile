# 0032: No "Not sent" for a send the server would have taken a moment later

Status: requested by the owner, 2026-11-12, after many messages showed "Not
sent" in v0.3.5 while "Send again" delivered them at once. Changes decision
0028 (the send window). No change to the rules, wire formats or keys.

## What went wrong

The server keeps the account's send clock (backend decision 0015): a day of
24 hours and a window of 10 seconds. The clock is in one of four states, and
the rules accept exactly one way of writing it in each:

| Day | Window | Form |
|---|---|---|
| runs | runs | `next`: `update({at, sent: +1, today: +1})` |
| runs | over | `window`: `update({at, window, sent: 1, today: +1})` |
| over | over | `day`: `set({at, window, sent: 1, day, today: 1})` |
| over | runs | `dayInWindow`: `update({at, day, today: 1, sent: +1})` (new) |

The app guesses the state, so a message needs no read first. Three things
together made it give up on messages that a moment later went through:

1. Near the end of a window it guessed "the window is over" about half a
   second early: it counted from before its last publish and took a margin
   off, when the server's window starts later than that, not earlier.
2. When `window` was refused it tried `day` next, which is always refused
   within a day, and `next` last. By the time `next` arrived, two round trips
   later, the window had often ended, so `next` was refused too: every form
   refused.
3. The fourth state had no form: a day that ended inside a running window
   refused every form for up to 10 seconds.

A model of the rules with the old order, mobile round trips of 50 ms to 1.5 s
and bursts of messages refused 1 to 4 % of sends, more on slow networks.

## What changes

- **All four forms**, tried in order of likelihood: the guess, then the other
  window state (a refused `window` means the window still runs, so `next`
  comes straight after), then the other day state, then both.
- **The guess** counts the window as running until 10 seconds after the
  publish that opened it began. Guessing `next` too late costs one refused
  attempt, after which `window` is certain; the old early guess could cost
  three. The wait for a used-up burst counts from the server's answer, the
  latest the window can have opened, so it is not cut short either.
- **Patience:** when every form is refused, all four are tried again after
  0.3 s and after another 1 s (`ChatTuning.refusalRetries`). Only refusals
  after which nothing was committed are retried (`permission-denied`,
  `not-found`, `unauthenticated` while the sign-in token is refreshed,
  `failed-precondition`). An unknown outcome (the network was lost) is never
  sent again by itself, as before: the person decides.
- **Order:** the retries happen inside the send's turn of the chat lock, so
  the next message in the queue waits behind it and cannot overtake it.
- A real refusal (a block, the daily cap reached on another device, a push
  challenge) now shows "Not sent" after the three rounds, about 1.5 s plus a
  few round trips later than before.

The loop is `publishWithClock` in `send_allowance.dart`, a pure function the
sender calls and the tests drive directly.

## What it costs

A normal send makes one write, as before. In the model a single device
chatting needs 1.03 attempts per message on average (the odd extra one near a
window's end); two devices of one account sending in turn, a worst case,
about 2.2. A refused attempt writes nothing. Its rules evaluation reads a few
documents (the device, the chat, the block, the profile and the send clock),
so a message that is really refused costs at most 12 attempts' reads, about
70 reads, once. That is rare: it means the person is blocked, at the cap or
challenged.

## Tests

`send_window_race_test.dart` drives `publishWithClock` and `SendAllowance`
against a model of the rules with a fake clock and jittered round trips: the
old order fails hundreds of times in 20,000 sends; the new one refuses none
in 600,000 (one device, two devices of one account, days ending inside
windows, sends faster than the burst). `pacing_test.dart`: the fourth form, a
second round, a token refresh, a lasting refusal (12 attempts, nothing
published), a refusal that cannot pass (one attempt), an unknown outcome
(never retried), and the order of two messages while one is retried.
`send_allowance_test.dart`: the guess at the window's end, a day ending inside
a window, the wait from the server's answer, and the try order.

Implementation assisted by Claude Code.
