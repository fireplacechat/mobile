# Continuous integration

The public client repository uses standard hosted runners. See GitHub's
[Actions billing documentation](https://docs.github.com/en/billing/managing-billing-for-github-actions/about-billing-for-github-actions).
No paid runner, service or plan is enabled.

- `ci.yml`: Linux analyzer, formatter and serial Flutter tests on code pushes/PRs; newer runs cancel older runs.
- `android.yml`: Linux compile candidate and APK permission, backup and signer regression checks on relevant changes or by hand.
- `ios.yml`: manual compilation only. Do not dispatch it without owner authorization.

Backend emulator checks belong to the separate private backend repository. CI never uses
production accounts. Android artifacts built with debug signing are compile candidates and
must not be distributed. Local equivalents are documented in [setup.md](setup.md) and
[android-release.md](android-release.md). Dependabot groups Actions updates; review and test updates before merging.
