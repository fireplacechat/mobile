# 0028: Send in bursts instead of one every 700 ms

Status: requested by the owner, 2026-11-12. Goes with backend decision 0015,
which changes the Firestore rules. No change to message payloads, the ratchet
or keys.

## Why

The rules allowed one message per account every 500 ms, so the app waited
700 ms between sends. A message right after a reaction, or two quick replies,
waited for that gap.

## What changes

The rules now allow up to **20 messages per account in a 10-second window**
(backend decision 0015). The average stays at 2 a second, the same as before,
so the worst case for cost and abuse is unchanged. Signal's server limits
messages the same way: a burst, then a steady refill rate.

The send clock `users/{uid}/limits/send` is written in the same batch as each
message, in one of three forms (`SendClock`):

- **open** a window: `set({at, window, sent: 1})`, both times the server time;
- **next**: count one more in it: `update({at, sent: increment(1)})`. This
  needs no read, because the update keeps the window the server holds;
- **legacy**: `{at}` with the older 700 ms gap, for a server still on the
  older rule.

`SendAllowance` follows the window on this device: it opens one when its own
last window is nearly over (a 500 ms margin), counts in it otherwise, and waits
for the window to end only when 20 have gone out. The server decides. When the
guess is wrong (another device of the account opened a window, or the clocks
differ), the write is refused and the other form is tried at once, with no read.

## Release order

If the server refuses both window forms, it may still be on the older rule.
The app then tries the older form after its gap, and keeps using it until the
app restarts. So this app works with the rules before and after the backend
change, and the backend keeps accepting older apps. A refusal for another
reason (a block, a request over its limit) fails every form and is reported as
before; that costs at most three refused attempts.

## Tests

`send_allowance_test` covers the decisions with a fake clock. `pacing_test`
covers the clock's forms, a wrong guess corrected by the other form, the
fallback to the older form and staying on it, a refusal that fails every form,
and (tagged `timing`) a burst going out without waiting and a used-up burst
waiting for its window. The backend's rules tests check the same write shapes
against the real rules.

Implementation assisted by Claude Code.
