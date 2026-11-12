# 0029: Count new chats and one-time prekey claims

Status: requested by the owner, 2026-11-12. Goes with backend decision 0017.
No change to message payloads, the ratchet or keys.

## What changes

The rules now cap two actions per account per day (backend decision 0017):
50 new chats and 200 one-time prekey claims. The app writes the counter in the
same batch or transaction as the action, with `DailyCounter`
(`model/common/daily_counter.dart`), in the same two forms as the send clock
(decision 0028): counting in the running day, or opening a new one. It
remembers which applies from its last success; a wrong guess is refused and
the other form is tried at once. If both are refused it tries once without a
counter: rules before backend decision 0017 refuse counters, so this keeps the
app working whichever is deployed first, and the newer rules allow it only for
an account that has never counted, so it is no way round the cap.

- **Starting a chat** (`ChatDirectory.startChat`) creates the chat and counts
  it in one batch. Refused in every form, the person reads: "You cannot start a
  chat with @name. If you have started many new chats today, try again
  tomorrow."
- **Claiming a one-time prekey** (`PreKeyService.fetchBundle`, which the sender
  calls with its own account as `claimer`) counts it in the claim's
  transaction. Refused in every form, the day's claims are used up: claiming
  stops and the session starts with the signed prekey alone, as it already does
  when a pool is empty. The person sees nothing.

## Tests

`daily_counter_test`: forms and their order, a refusal retried in the other
form, the attempt without a counter, a refusal in every form passed on, other
failures not retried, chats and claims counted, and the fall-back to the signed
prekey when claims are refused.

Implementation assisted by Claude Code.
