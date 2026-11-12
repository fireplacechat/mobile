# 0028: Send in bursts, within a daily cap

Status: requested by the owner, 2026-11-12. Goes with backend decision 0015,
which changes the Firestore rules. No change to message payloads, the ratchet
or keys.

## Why

The rules allowed one message per account every 500 ms, so the app waited
700 ms between sends. A message right after a reaction, or two quick replies,
waited for that gap. And nothing limited how much one account could send in a
day: about 170,000 messages at 2 a second, which on the Blaze plan is a bill.

## What changes

The rules now allow, per account across all chats (backend decision 0015):

- up to **20 messages in a 10-second window**: a burst goes out at once, and
  the average stays at the earlier 2 a second;
- up to **2,000 messages a day** (reactions included), counted over 24 hours
  from the first one. Past that, sends are refused until the day ends.

This follows Signal: its server limits sending with a burst and a refill rate
and slows people down rather than banning them; bans come from review and a
private spam filter. Here, `fp-ops limited` lists accounts at the cap for the
owner to review.

The send clock `users/{uid}/limits/send` is written in the same batch as each
message, in one of four forms (`SendClock`). None needs a read: an update keeps
what the server already holds and adds one.

- **day**: `set({at, window, sent: 1, day, today: 1})`, all times the server
  time, for the first message ever or once the last day is over;
- **window**: `update({at, window, sent: 1, today: +1})`, a new window in the
  running day;
- **next**: `update({at, sent: +1, today: +1})`, one more in the window;
- **legacy**: `{at}` with the older 700 ms gap, for a server still on the
  older rule.

`SendAllowance` follows the window and the day on this device, with margins
for clock differences (500 ms and a minute), and picks the form. It waits for
the window to end only when 20 have gone out. When this device alone has sent
2,000 in its day, a send stops before anything is encrypted and says when
sending works again. The server decides in the end: a wrong guess (another
device of the account opened a window or day, or the clocks differ) is refused
and the other forms are tried at once, likeliest first.

## Release order

If the server refuses all three new forms, it may still be on the older rule.
The app then tries the older form after its gap, and keeps using it until the
app restarts. So this app works with the rules before and after the backend
change, and the backend keeps accepting older apps. A refusal for another
reason (a block, a request over its limit, the cap reached on another device)
fails every form and is reported as before; that costs at most four refused
attempts.

## Tests

`send_allowance_test` covers the decisions with a fake clock: forms, margins,
the waits, the cap and its end, a window or day opened by another device, the
older form. `pacing_test` covers the clock's fields, the local cap stopping a
send before it is published, a wrong guess corrected by another form, the
fallback to the older form and staying on it, a refusal that fails every form,
and (tagged `timing`) a burst going out without waiting and a used-up burst
waiting for its window. The backend's rules tests check the same write shapes
against the real rules.

Implementation assisted by Claude Code.
