# fireplace.

<p align="center"><img src="docs/assets/readme-banner.png" alt="fireplace." width="100%"></p>

<p align="center">
  <a href="https://github.com/fireplacechat/mobile/actions/workflows/ci.yml"><img src="https://github.com/fireplacechat/mobile/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI status"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-BF5700?style=flat" alt="License: AGPL-3.0"></a>
  <img src="https://img.shields.io/badge/platforms-iOS%20%7C%20Android-333F48?style=flat" alt="Platforms: iOS and Android">
  <img src="https://img.shields.io/badge/built%20with-Flutter-02569B?style=flat&logo=flutter&logoColor=white" alt="Built with Flutter">
</p>

Fireplace is a private, end-to-end encrypted messenger for the people you actually talk to. Messages are sealed on your phone and can only be opened on theirs.
This repository is the mobile app (iOS and Android), written in Flutter.

**Status:** in development, pre-beta. It is not available in the app stores yet. Do not rely on it for sensitive use until a stable release says otherwise.

## What is here

- **Private by design.** Hybrid post-quantum key exchange (X25519 + ML-KEM-768), hybrid signatures (Ed25519 + ML-DSA-65) and a double ratchet. Chat message content is encrypted before upload. Reports can include selected message text only when the reporter chooses to share it.
- **No phone number, no email.** Username and password, joined with an invite.
- **Verifiable.** Safety numbers and QR codes; a changed key holds the conversation until you review it.
- **Open.** AGPL-3.0, with the design decisions in [docs/decisions](docs/decisions) and the [threat model](docs/protocol/threat-model.md).

## Get started

Install [Flutter](https://docs.flutter.dev/get-started/install) (the version pinned in `pubspec.yaml`), then:

```sh
flutter pub get
flutter analyze
TZ=UTC flutter test --concurrency=1
```

To run the app against a local backend, and for Android and iOS builds, see [docs/development/setup.md](docs/development/setup.md).

## Repository layout

| Path | What it holds |
|---|---|
| `lib/` | the app: `src/crypto` (protocol), `src/services` (storage, networking), `src/app` (providers, session), `src/ui` (screens and widgets) |
| `test/`, `integration_test/` | unit, widget, simulation and integration tests; protocol test vectors in `test/vectors` |
| `android/`, `ios/` | platform projects |
| `assets/` | icons and artwork bundled in the app |
| `scripts/` | developer scripts: APK checks, screenshot renders, emulator helper |
| `docs/` | contributor and protocol documentation ([index](docs/README.md)) |
| `.github/` | CI workflows and issue and pull request templates |

This public repository contains the mobile client. Backend rules and operator tools are maintained separately in a private repository; they are not included here. The project website is https://fireplacechat.com.

## Contributing

We welcome bug fixes and tests most of all. Read [CONTRIBUTING.md](CONTRIBUTING.md) and the [coding style](docs/development/coding-style.md) first. Humans and AI tools both work here;
see [AGENTS.md](AGENTS.md) and the [AI usage policy](AI_POLICY.md).

Report security problems privately, as described in [SECURITY.md](SECURITY.md).

## License

Code: [AGPL-3.0](LICENSE). The Fireplace name, logo and artwork are not covered by that licence; see [TRADEMARKS.md](TRADEMARKS.md).
Third-party notices: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
