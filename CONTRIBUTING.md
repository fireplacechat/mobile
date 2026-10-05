# Contributing to Fireplace

Fireplace is an open-source (AGPL-3.0) end-to-end encrypted messenger built with Flutter. We want it to be simple, dependable, free, with no ads and no tracking. Thank you for helping.

Before a large change, open an issue or discussion to agree the scope. New features that do not fit the project's goals may be declined, so ask first.

## Set up
Install Flutter (the version pinned in `pubspec.yaml`) and the Android SDK or Xcode, then `flutter pub get`. See [docs/development/setup.md](docs/development/setup.md). Never use real accounts or real conversations for testing.
Conventions for people and AI tools: [AGENTS.md](AGENTS.md) and the [coding style](docs/development/coding-style.md).

## What to work on
Bug fixes and tests are the most welcome contributions: widget and service tests are fast and reliable. Check existing issues and pull requests to avoid duplicate work, and open a draft pull request early.

## Before you open a pull request
- Keep it small and focused, with the reason in the description.
- Do not commit passwords, keys, signing material, recovery codes, service-account files or real user data.
- Do not change cryptographic wire formats, key handling or authentication without a design discussion, a note in `docs/decisions/` and tests.
- Run `flutter analyze`, `dart format` and `TZ=UTC flutter test --concurrency=1`. If something cannot run locally, say why.
- UI changes need a screenshot or a short recording.
- If an AI tool helped, say so and follow the [AI usage policy](AI_POLICY.md).

## Reporting problems
Use the issue templates, include the app version, device and OS, and redact personal data. Report vulnerabilities privately as described in [SECURITY.md](SECURITY.md).
