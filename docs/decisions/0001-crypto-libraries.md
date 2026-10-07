# 0001: Crypto libraries (Phase 0 spike)

Date: 2026-10-03. Status: accepted.

Checked on pub.dev: `pqc_e2ee` 1.0.0 (no repository link), `sk_pqc` 0.1.0, `pq_aura_flutter` 0.1.0, `flutter_pqc` 0.0.3, `pqcrypto` 0.4.2, `pqforge` 0.4.6, `cryptography` 2.9.0.

**Decision:** use `pqcrypto` (pure-Dart ML-KEM FIPS 203 / ML-DSA FIPS 204, ships KAT/ACVP vectors, no native deps, works on iOS/Android/web) + `cryptography` (X25519, Ed25519, HKDF, AES-256-GCM). We write the handshake/ratchet glue ourselves in `lib/src/crypto/` with our own tests.

**Rejected as dependencies:** `pqc_e2ee`, `sk_pqc`, `pq_aura_flutter` (0.x / single maintainer / no audit, or no source link; protocol logic should be ours and reviewable). They remain useful as references.

**Caveats:** The classical primitives from `cryptography` also use Dart implementations on Android/iOS in the current configuration; no `cryptography_flutter` provider is enabled. Browser builds can use Web Crypto with Dart fallbacks. Neither this configuration nor the protocol is claimed to be constant-time-hardened. `pqcrypto` is not CMVP/FIPS-140 validated and pure Dart is not constant-time-hardened; independent cryptographic and side-channel review remains outstanding. Spike test: `test/spike/pq_library_spike_test.dart` (passes).
