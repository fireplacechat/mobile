# 0049: Invite page

Date: 2026-11-14. Status: proposed (issue #115). Server side: backend decision 0021,
which holds the rules, the operator tools and their costs. Builds on 0048 (account
deletion isolation).

## What people see

A `+` in a circle at the top left of the chat list, in the theme's accent colour,
opens the Invite page. It slides in from the left and its back arrow is at the top
right. The `fireplace.` lockup is centred at the top of the chat list.

Each invite row is a ticket:

- **Ready:** *Create a code*.
- **Locked:** a live countdown to when it unlocks (`6d 23:14:08`).
- **A code:** the code, *Copy code*, *Replace*, and *Unused* or *Used*. A used code is
  struck through. Nothing says who used it.

When the operator pauses invites, a notice says so and *Create a code* is disabled.
With no rows the page says *You have no invites right now.*

## How it works

- The page listens to `config/invites`, `inviteAllowances/{uid}` and the account's
  `inviteSlots`, so the operator's changes show at once. It reads `createdAt` once.
  The listeners stop when the page closes.
- The app makes a 16-character code with `Random.secure()` and writes the row and the
  invite in one batch. The rules decide whether it may; the app only mirrors them.
- A write that may have reached the server is never retried. After 20 seconds the page
  says the code was not confirmed and shows it if it was saved. A row with unconfirmed
  local writes shows *Saving…* and cannot be copied.
- If the countdown ends but the server still refuses (the phone's clock runs fast),
  the page says so in plain words.
- Sign-up: before the profile batch, the app tries to read the invite. A person's code
  is readable while unused and names its row; the batch then also marks that row used.
  Operator codes cannot be read, and the batch is as before.
- The code is drawn in the normal typeface, not monospace: codes contain the letter O
  but never zero, and the monospace O looks like a zero.

## Account deletion

Each row holds its code in clear, so deleting the account deletes them (0048's
named-records step): the rows, and the invite of each unused code. Used invites stay,
as backend 0021 and 0022 keep used invite records. A retry may find an invite gone or
already refused; that does not stop the deletion, because the server refuses every
code of a deleting or deleted account anyway. The Invite page's listeners belong to
the signed-in account and stop when 0048 drops the session.

## Emulator builds

`--dart-define=EMULATOR_FIRESTORE_PORT=8180` points the app at a Firestore emulator on
another port, for machines where a system service holds 8080.

## Tests

`test/model/invites/` (rows, schedule, codes, service writes, sign-up marking the row)
and `test/view/invites/invite_screen_test.dart` (ready and countdown rows, copy, a
refused create shown in plain words and not retried, replace and its wait, used rows
show no usernames, pause, live operator changes, the home `+` and back arrow, the
empty page). Checked end to end on an Android emulator against the backend rules.

AI assistance: Claude Code.
