# 0011: Beta fixes from the 2026-10-04 review (age declaration, sync paging, deletion fence)

Status: implemented on branch `feature/beta-fixes`. **The security-rules changes need owner deployment with `firebase deploy --only firestore:rules` to take effect.**
Records the age declaration, sync paging and deletion-fence implementation. Backend tooling and publishing gates are maintained separately in private repositories.

## 1. Sign-up age declaration (16+)
- `lib/src/ui/auth_screen.dart`: in Create account mode only, an unchecked **"I am 16 or older"** checkbox below the invite code. The
  Create account button is disabled until it is ticked; keyboard submission is guarded too (no Auth call, inline error "You must be 16
  or older to join this beta."). Switching modes resets it; it is disabled while signing up. A line under it points to the terms and
  privacy pages.
- No date of birth or identity document is collected, and nothing is stored: it is an eligibility self-declaration, not a verified age
  check and not server enforcement. Under-16 accounts are handled by the operator with `fp-ops delete` (see the UI spec).
- Tests: `test/ui/auth_screen_age_test.dart` (7), and the existing sign-up widget test now ticks the box.

## 2. Sync paging (P1: "sync can continuously reopen a full page without progress")
- The durable **cursor** stays a recovery watermark that never passes an unfinished message. The **page position** is now separate and
  in memory: each full page is followed by a query that starts right after the last document read (`startAfterDocument`, so ties on
  the timestamp are broken by document id). Every page therefore moves forward, even when the cursor is held back, and 500 or more
  messages sharing one timestamp no longer stall. Unfinished messages are retried from memory (`retryDeferred`), not by re-reading.
- Tests: `test/services/sync_paging_test.dart`: 1,200 equal timestamps are reached in 3 pages with no message read twice; a full
  page with an unfinished first message makes progress, opens 3 pages, and keeps the cursor held; live messages still arrive after a
  backlog; the cursor still advances when nothing is unfinished. With the old behaviour the first test hangs (a hot loop).

## 3. Operator deletion (P1 write fence, P2 completion audit)
- **Fence in the rules.** `notDeleting(uid)` is required on every create and update an account's own devices can make (profile,
  devices, prekeys, push tokens, recovery backup, link requests, blocks, reports, send clock, chats, messages). Deletes stay allowed,
  so a deletion can always finish. The flag is set by the app's own deletion and by `fp-ops delete`.
- **`fp-ops delete` order:** record the intent in `deletionJobs/{uid}` (uid, username, reason, phase, times, attempts; never message
  content) -> fence (disable sign-in, revoke tokens, `deleting: true`) -> list targets only after the fence -> delete messages,
  devices and prekeys, small collections, the username (only if it still belongs to this uid) -> `recursiveDelete` of the profile so
  unknown subcollections go too, then verify nothing is left -> delete the sign-in account -> write the audit entry and mark the job
  completed in ONE batch.
- **Resumable.** If a step fails, the job stays `started`. Run `fp-ops delete <uid> --reason "..." --yes` again (use the uid, not the
  username: the name is released and may belong to someone else by then). It finishes the clean-up and writes the missing audit entry.
  `fp-ops delete <uid> --dry-run` says when it would resume an earlier deletion.
- Tests: rules (2 new, 1 updated) and operator (4 new): the fence is in place before anything is listed; records added after the
  fence and unknown subcollections are removed; a failed audit is completed by a retry; username ownership checks are exercised; this is not a guarantee against all concurrent operator runs.

## 4. Release signer check (P2: "release validation accepts debug-signed release artifacts")
- `android/app/build.gradle.kts`: `-Pfireplace.distribution=true` fails the build when `key.properties` is missing or incomplete (it used
  to fall back to the debug key silently). The ordinary build is unchanged, so CI still compiles.
- `scripts/check_apk.sh`: the signature must verify; `--distribution` also requires one signer, not the debug key, and an exact match with the
  upload-key SHA-256 in `android/upload-cert.sha256`. Ordinary mode flags a debug-signed APK as "NOT distributable". Tested by
  `scripts/test_check_apk.sh` (12 cases, run in CI). Nothing was signed with, or copied from, the real key.

## 5. Legal publishing gate (P2: "legal publishing gate misses blank placeholders")
- `site/gate.py` decides whether /privacy/ and /terms/ may be published. Both must hold: **no open items** and **a recorded approval**.
  Open items: an unresolved `[bracketed decision]`, a **blank `[ ]` / `[]` field in running text** (the old rule needed two characters inside
  the brackets, so it missed the effective-date and contact fields), or an internal note such as "Publication gate" or "Not ready to publish".
  Real task-list checkboxes (`- [ ] item`) are not blank fields.
- **Approval is explicit:** the page source must start with `<!-- publish: approved YYYY-MM-DD -->`. A text with no placeholders but no
  approval stays a draft. The line is removed from the published HTML.
- `python3 site/build.py --draft` builds draft previews, always `noindex` with a banner listing what still blocks publication, **including
  when the last placeholder has just been filled in** but nobody has approved the text. Approved, clean pages are indexable in either mode.
- Website/legal sources are maintained separately; policy changes still require explicit owner approval and deployment.
- Tests: `python3 -m unittest discover -s site/tests -v` (17: the rules, and real builds on a temporary copy for each scenario).

## 6. Auth-error screen and splash clipping
- `lib/src/ui/app.dart`: a terminal auth-stream error now shows "Try again" (re-subscribes) and "Sign out", not a dead end.
- `lib/src/ui/lockup.dart`: the splash keeps the lockup exactly centred when there is room (the same place as the native launch screen);
  when the area under it is too small (a short screen or a large text size) the lockup, message and buttons scroll together, so nothing is
  clipped. Tests: `test/ui/auth_error_test.dart` (320x480 at 200% text, recovery, sign-out failing offline).

## 7. "Message not confirmed" (decision 0009 / UI handoff 1)
- `ChatService.sendText` now throws `SendNotConfirmedException` (outcome `publishUnknown` or `publishedLocalSaveFailed`, stable message id,
  body, `persisted`) instead of a plain error when the message may exist. An `unconfirmed` entry is kept in the encrypted history, so the
  warning survives a restart; if even that fails the UI keeps it in memory.
- `checkSendStatus` reads from the server only and never publishes; sync resolves the warning by itself when our own message shows up (a
  failed repair write is deferred and retried, found by the randomized simulation); `saveSentLocally` repairs history only;
  `resendUnconfirmed` is an explicit, confirmed new message with a new id.
- UI (`chat_screen.dart`): "Message not confirmed" / "Sent - could not save on this device", Check status, Send again... (with a
  "Send another copy?" dialog), live-region announcement, edits made during the send survive.
- Tests: `test/services/send_outcome_test.dart` (14), `test/ui/message_not_confirmed_test.dart` (9), plus updated simulation invariants.

## Still open (not covered here)
- Account deletion in the app (`AccountService`) still runs from the phone: compatible with the fence, but without a durable job record.
