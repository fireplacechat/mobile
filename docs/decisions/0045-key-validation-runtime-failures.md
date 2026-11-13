# 0045: Preserve keys when the crypto runtime is unavailable

Status: proposed during the v0.3.7 iOS upgrade investigation.

The device-setup screen is not proof that local private keys were lost.
`ensureDevice` previously caught every exception while parsing and validating
stored keys and converted it to `NeedsRecoveryException`. A missing native
library or symbol therefore offered recovery and destructive identity reset
even with intact, consistent key records.

Only malformed stored JSON/types are converted to recovery during parsing.
Cryptographic validation runs outside that catch: false consistency or
certificate checks still refuse readiness and require explicit recovery;
runtime errors propagate to the existing retryable startup error screen.
No fallback backend, replacement keys, implicit republishing or diagnostics
containing key material are introduced.

Identity reset generates both replacement key pairs before deleting anything.
A crypto initialization/generation failure preserves the existing local keys,
device registrations and encrypted backup. This is a bounded safety fix, not
an atomic reset redesign: later certification, storage or network failures can
still interrupt the existing reset procedure. Durable reset journaling needs
a separate design. Existing key formats, wire formats and rules do not change.

Tests generate fictional keys using the Dart reference, then use a zone-local
file override to make the actual Rust library lookup fail. Startup must expose
the operational failure rather than claim missing keys; reset must leave every
local record, device and backup unchanged. Both assertions fail on v0.3.7.
Malformed JSON, wrong types, mismatched private/public halves and invalid
certificates remain recovery failures with both working backends. Successful
reset and recovery/linking retain their existing tests.

There are no added Firestore operations, server fields, dependencies, network
requests or permissions. A failed replacement generation now avoids the reads
and deletions that previously preceded it. No conclusion about the underlying
iOS upgrade regression follows from this safety change; signed configuration
and on-device validation are still required.

Implementation assisted by OpenAI Codex.
