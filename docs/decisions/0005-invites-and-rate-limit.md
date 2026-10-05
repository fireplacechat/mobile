# 0005: Invite-only sign-up and enforced send pacing

Date: 2026-10-03. Status: accepted. Responds to the cost/abuse analysis in `docs/push/COSTS.md`: on the free Spark plan an abuser can only cause an outage, but on any paid plan unlimited writes become a bill, and sign-up was open to anyone.

## Invite-only sign-up
- The operator creates single-use invites (`fp-ops invite create`). Each is a document `invites/{sha256(code)}`; the code (16 characters, 80 bits) is shown once and never stored.
- Sign-up is one atomic batch: username claim + profile (with the invite id) + marking the invite `usedBy`. The rules accept the profile only if that invite exists, is unused and is claimed by the same uid in the same batch. Clients cannot read, list, create, edit or delete invites.
- Firebase Auth itself still lets anyone create a login (turning that off needs Identity Platform blocking functions, i.e. a paid plan). So **every other write that costs us anything requires an existing profile** (`hasProfile`): devices, prekeys, recovery backup, link requests, blocks, reports, send clock, and *reading* usernames, profiles, devices and prekeys. An account created without an invite can do nothing except look at its own (absent) profile.
- Cost: one extra rules read on those operations (the client already rarely does them).
- Limits: a leaked invite works for whoever uses it first; invites are not tied to a person; nothing stops a legitimate invitee from inviting abuse (the operator controls how many invites exist).

## Send pacing
- Every message is written in a batch together with the sender's clock `users/{uid}/limits/send` set to the server time. The rules require the previous value to be at least 500 ms older, **per account across all chats**, and the new value to equal `request.time` (cannot be forged or skipped).
- Honest use never gets close: the app waits 700 ms between sends and retries once if the server still refuses.
- Bound: at most 2 messages/second per account = 172,800/day. Combined with invites, total possible write volume is (number of accounts) x that, and the operator controls the number of accounts and can ban any one.
- Cost for honest users: one extra write per message (the clock); the chat list timestamp is now bumped at most once per minute, which removes most of the old second write.

## What this does NOT protect
- A bill from a bug in our own code (rate limit applies to messages only).
- Reads: listeners and rules reads are not rate limited (App Check is the follow-up).
- A compromised invitee account can still send 2 messages/second for as long as it exists; the ban tool (up to an hour for token expiry) ends it.
- Cloud Functions / Blaze remain off. See `docs/push/COSTS.md`.
