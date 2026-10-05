# Third-party notices

Fireplace includes dependencies resolved in `pubspec.lock`. Their licence notices are available in the app through Settings → Open-source licences, using Flutter's licence registry. Preserve the notices and licence terms supplied with each dependency.

The following external test data is included:

- `test/vectors/nist_mlkem768.json` and `test/vectors/nist_mldsa65.json`: NIST post-quantum known-answer vectors. Source: https://github.com/usnistgov/ACVP-Server.
- `test/vectors/wycheproof_classical.json`: the fixture metadata identifies Google Wycheproof / C2SP testvectors_v1, licensed Apache-2.0. Source: https://github.com/C2SP/wycheproof.

Use `dart pub deps --style=list` to inspect resolved dependencies and check their licence notices when changing packages. This file does not replace those notices.

The repository's `LICENSE` covers Fireplace code. The name, logo and artwork are addressed separately in [`TRADEMARKS.md`](TRADEMARKS.md).
