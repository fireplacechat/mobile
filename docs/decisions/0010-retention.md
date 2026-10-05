# 0010: Expiry eligibility and operator cleanup

Corrected 2026-10-05. The previous decision incorrectly described Firestore TTL deletes as
available on Spark. They require billing; no TTL policy or paid scheduler is used. Code is
implemented and tested locally; production deployment and an operating schedule remain owner tasks.
See [Firebase's official billing documentation](https://firebase.google.com/docs/firestore/pricing).

## Decision

Messages carry `expireAt` (send timestamp + 30 days), validated by the rules within their clock
tolerance. That field marks eligibility for an operator purge; it does not delete a document or
guarantee a retention period. Devices keep their own encrypted local history independently.

Inactive-account tooling uses a 13-month inactivity threshold. It is run manually and depends on
the existing deletion workflow. No automatic account-deletion deadline, advance notice or sweep
frequency is promised. Other retention categories remain undecided.

## Free-plan implementation

- `firestore.indexes.json` has no TTL entry.
- `fp-ops expire-messages` only backfills legacy expiry metadata; it does not delete messages.
- `fp-ops purge-messages --dry-run` previews a bounded message scan; `--yes` applies it. Default:
  at most five pages of 200 documents. Limits are capped at ten pages of 200. Reads and deletes
  consume the existing Firestore quotas; bound each run and check usage.
- Order is full document path, requiring no expiry-query index. A printed cursor resumes after
  the last successfully committed page, including if that cursor's document was deleted.
- Keep the printed `--before` cutoff and `--cursor` when continuing. A completed sweep is followed
  by a future sweep from the beginning; newly inserted records before the cursor wait until then.
- Deletion candidates are reread in a transaction. Changed expiry or already-removed records are
  rechecked. Legacy records without expiry derive eligibility from a valid server timestamp; malformed
  or missing dates are skipped. An unexpected collection path stops the run without deleting that page.
- No server-side cursor or scheduling document is stored. Failure prints the last committed progress;
  replay is idempotent. No message content is printed or inspected.
- `fp-ops inactive` previews accounts; `--delete --yes` applies the existing account deletion.

## To operate (owner only)

Deploy rule changes with `firebase deploy --only firestore:rules`; do not deploy a TTL index.
Older app builds without expiry metadata cannot send after the relevant rules are deployed.
Preview purge results, run bounded batches, retain the printed progress locally, and choose an
operating schedule compatible with quota. No production deployment was performed for this change.

## Wording

No public retention/deletion-period promise is approved by this implementation. Policy wording remains subject to owner and legal approval. Deployment, routine execution,
vendor backup behaviour and legal review must be confirmed before a policy promises timings.

Tests cover dry runs, bounds, deleted-cursor resume, malformed dates, transaction rechecks,
partial failure/retry and unrelated collections. Implementation assisted by Codex.
