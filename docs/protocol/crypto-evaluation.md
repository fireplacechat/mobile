# Protocol overview

Fireplace uses X25519 + ML-KEM-768 for its hybrid key exchange and Ed25519 + ML-DSA-65 for
hybrid identity signatures. The ratchet uses AES-256-GCM for message encryption. See the
[threat model](threat-model.md) and [design decisions](../decisions/) for scope and assumptions.

This document is an algorithm inventory, not an independent audit or security certification.
Standards vectors, property tests and service simulations are included in `test/`; they do not
establish that the full application is secure. Historical review reports remain private.
