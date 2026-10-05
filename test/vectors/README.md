# Test vectors

Third-party known-answer vectors used by `test/crypto/nist_vectors_test.dart` and
`test/crypto/wycheproof_test.dart`. They are data, not code, and are not edited by hand.

| File | Source | Used for |
|---|---|---|
| `nist_mlkem768.json` | NIST ACVP-Server `gen-val/json-files/ML-KEM-keyGen-FIPS203` and `ML-KEM-encapDecap-FIPS203` (prompt + expectedResults merged), ML-KEM-768 only | key generation, encapsulation, decapsulation, key checks |
| `nist_mldsa65.json` | NIST ACVP-Server `ML-DSA-keyGen-FIPS204`, `ML-DSA-sigGen-FIPS204`, `ML-DSA-sigVer-FIPS204`, ML-DSA-65, external/pure interface only | key generation, signing (deterministic and hedged with a supplied `rnd`), verification incl. invalid signatures |
| `wycheproof_classical.json` | Google Wycheproof (C2SP/wycheproof `testvectors_v1`): `x25519`, `ed25519`, `aes_gcm` (256-bit key, 96-bit IV, 128-bit tag), `hkdf_sha256` | X25519, Ed25519, AES-256-GCM, HKDF-SHA256 |

Regenerate by downloading the upstream files, merging each `prompt.json` with its
`expectedResults.json` by `(tgId, tcId)`, and keeping only the groups listed above.
Both upstream projects are public and permissively licensed (NIST: public domain; Wycheproof: Apache-2.0).
