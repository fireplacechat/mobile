# 0020: Contributory key exchange and linking timeout cleanup

Date: 2026-10-07. Status: proposed for review.

## Decision

Reject an X25519 shared secret when all 32 output bytes are zero. Session
handshakes and both ratchet directions share the same checked DH function.
Device linking checks the DH contribution before deriving the sealing/opening
key. Keep the existing hybrid KDF, wire fields, protocol version and key sizes.
Valid existing exchanges derive identical keys. Recovery backups use a random
recovery key and HKDF, not X25519; they need no DH check.

[RFC 7748 section 6.1](https://www.rfc-editor.org/rfc/rfc7748.html#section-6.1)
permits this rejection and describes scanning the output with a bytewise OR.
This implementation scans every byte, without claiming constant-time Dart
execution. Rejecting non-contributory input keeps both hybrid components active.
Failures do not commit ratchet state; the existing clone-and-commit boundary stays.

When waiting for a linking response times out, delete only that request document,
including any response arriving concurrently. Approval uses update and cannot
recreate it after deletion. Report cleanup failure honestly and allow the existing
retry flow to attempt cancellation again. Cancellation and successful completion
already delete the request. This adds no fields, TTL indexes or backend services.
An offline/crashed client cannot guarantee deletion by a deadline; an approved
response awaiting confirmation has no automatic expiry in this change. Linking
transfers remain encrypted to the new device keys and are not forward-secret.

## Provider configuration

Correct the documentation for both classical and post-quantum Dart implementations.
Do not add a native provider in this change. Platform coverage and fallbacks vary:
[cryptography_flutter documentation](https://pub.dev/packages/cryptography_flutter)
lists native X25519/Ed25519 support on Apple platforms. A provider migration needs
cross-provider vectors, persisted-key/session interoperability checks and real
Android/iOS verification before adopting it. It does not remove the need for an
independent cryptographic and side-channel review.

## Validation

Regression tests reject signed low-order prekeys, handshake ephemerals and linking
recipient points; normal handshake, ratchet, linking and standards-vector tests
remain in place. Timeout tests check deletion isolation and that no identity or
device is installed. No changes to Firestore rules, storage schema or deployment.
