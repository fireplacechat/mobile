# Account deletion

Apple's App Review Guideline 5.1.1(v) requires apps that let people create an account to let them delete it **inside the app**. In Fireplace: **Settings → Delete account**. It asks the user to type their username and re-enter their password, then runs `AccountService.deleteAccount` (`lib/src/model/account/account_service.dart`).

## What is deleted
| Data | Where | How |
|---|---|---|
| Sign-in account (synthetic email + password hash) | Firebase Auth | `User.delete()`, then explicit local signout |
| Username claim, public profile | Firestore `usernames/{name}`, `users/{uid}` | deleted; the username becomes available again |
| Devices, public keys, certificates, prekeys | `users/{uid}/devices/*` and `.../prekeys/*` | deleted |
| Recovery-key backup, link requests, block list | `users/{uid}/private`, `linkRequests`, `blocks` | deleted |
| Every message the user sent | `chats/*/messages` where `senderUid == uid` | deleted in batches |
| Keys, sessions, message history, settings on the phone | Keychain / Keystore, encrypted message files | owner-scoped erasure; other local accounts are preserved |

Deletion addresses `limits/send`, `limits/chats`, `limits/claims` and
`challengeProof/current` by name; their collections cannot be listed. Files are
removed from both legacy and iOS shared history roots even when deletion resumes
without a normal chat session. Theme, colours and send sound are account-scoped;
deleting one account resets its choices without resetting another account.
See [decision 0048](../decisions/0048-account-deletion-isolation.md).

## What remains, and why
- **Messages other people sent to this account** remain encrypted on the server until the sender explicitly removes the conversation or deletes their own account. Deletion removes the recipient's keys on this phone. Other people's local history is preserved when they open their chat list.
- **Messages already delivered** to other people's devices stay on those devices; the sender cannot remove them (same as every encrypted messenger).
- Firebase may keep routine infrastructure logs and backups for a limited time under its own policies. Message text is not stored in a report.

## Failure handling
Deletion is a sequence of idempotent steps. Before deleting anything the profile is flagged `deleting: true`; if the app is closed or loses network mid-way, the next sign-in shows **Finish deleting** instead of the normal app, and the same steps run again. If only the final sign-in-account removal fails, the data is already gone and the user is told to sign in again and retry.

## For App Review notes
"Account deletion: open Settings (gear icon) → Delete account → type your username and password → Delete my account. This removes your account and data immediately."

## When the person cannot sign in (operator-assisted)
Someone who lost both their phone and their password cannot use the in-app flow. The operator tool does the same deletion from the server: `fp-ops delete <name> --dry-run` to preview, then `fp-ops delete <name> --reason "..." --yes` (see `tools/operator/README.md`). Because accounts have no email or phone, the operator must decide whether the requester owns the account before running it; the tool records the reason in the moderation log. The public instructions are on `/delete-account/` (site/pages/delete-account.md).
