# Continuous integration

The public client repository uses standard hosted runners. See GitHub's
[Actions billing documentation](https://docs.github.com/en/billing/managing-billing-for-github-actions/about-billing-for-github-actions).
No paid runner, service or plan is enabled.

- `ci.yml`: on code changes only. Runs side by side: `static` (formatter, analyzer, layer checker), three `unit` test shards, and `timing` (tests that measure real time, one at a time). A final job named `test` collects them and is the check branch protection requires; do not rename it. Newer pull-request runs cancel older ones.
- `android.yml`: Linux compile candidate and APK permission, backup and signer regression checks on relevant changes or by hand.
- `ios.yml`: manual compilation only. Do not dispatch it without owner authorization.

Backend emulator checks belong to the separate private backend repository. CI never uses
production accounts. Android artifacts built with debug signing are compile candidates and
must not be distributed. Local equivalents are documented in [setup.md](setup.md) and
[android-release.md](android-release.md). Dependabot groups Actions updates; review and test updates before merging.
