# 0004: Abuse controls (message requests, blocking, reporting)

Date: 2026-10-03. Status: accepted. Responds to review R3 and the App Store requirement for user-generated-content safety (block + report).

## Message requests
- A chat document records `initiator`, `accepted` (false at creation) and `requestCount`.
- Until the other person accepts, the initiator can send at most **3** messages. The Firestore rules enforce it: the message create must be in the same batch as a chat update that bumps `requestCount` by exactly 1 (max 3).
- The recipient accepts explicitly (`accepted: true`) or by replying (the reply batch sets `accepted`). Only the non-initiator can accept; acceptance cannot be undone; participants/initiator are immutable.
- The app does **not** start syncing or decrypting an incoming, unaccepted request. A stranger therefore cannot consume our one-time prekeys or fill local storage, and nothing they wrote is shown until accepted. Accepting starts sync, and the cursor logic fetches what was waiting.
- "Ignore" hides a request locally (SecretStore); it is not a server-side delete (the rules forbid deleting chats).
- Chats created before this change (no `accepted` field) are treated as accepted.

## Blocking
- `users/{me}/blocks/{peer}` (owner-only). The rules deny chat creation and message creation when the recipient has blocked the sender (`exists()` check; the blocked person gets a generic permission error and cannot read the block list). The blocker may still write (e.g. to say goodbye).
- Client side: a blocked peer's chats are not synced, anything still in flight is dropped on receipt, and sending/starting chats with someone you blocked is refused with a clear message.

## Reporting
- `reports/{reporter}_{reported}`: create/update by the reporter only, write-only for clients (read it in the Firebase console). Reason from a fixed list, optional note (<=500), optional chat id, optional context (<=20 lines, each trimmed to 1000 chars).
- Messages are end-to-end encrypted. The only message text the operator can ever see is what the reporter chooses to attach (opt-in checkbox, default off). **It cannot be verified** (a reporter could fabricate it). Message franking would fix that and is future work.

## Costs and limits
- Each message write now costs 3 rule-evaluation reads (chat doc, sender device doc, block check). Still within free-tier for friends & family; a public launch will need the Blaze plan anyway.
- This does not stop a determined attacker from creating many accounts and many requests. Remaining items for public launch: App Check (needs the Apple account), per-account creation limits, operator tooling to act on reports (there is none yet), account deletion.
