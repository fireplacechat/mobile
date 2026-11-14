# Documentation

| Task | Read |
|---|---|
| Set up the app or run tests | [Development setup](development/setup.md) |
| Find the code for a feature | [Architecture](architecture.md) |
| Make a contribution | [Contributing](../.github/CONTRIBUTING.md), [coding style](development/coding-style.md), [repository rules](../AGENTS.md) |
| See what exists and what is planned | [Feature status](roadmap/feature-matrix.md), [roadmap](ROADMAP.md) |
| Understand security boundaries | [Threat model](protocol/threat-model.md), [crypto overview](protocol/crypto-evaluation.md), [account deletion](protocol/account-deletion.md) |
| Work on group chats | [Implementation specification](protocol/group-chats-v1.md), [owner decisions](decisions/0050-group-chats.md), [design rationale](protocol/group-chat-design.md) |
| Check or preview a change | [CI](development/ci.md), [screen renders](../scripts/render/README.md), [iOS previews](development/ios-previews.md) |
| Prepare a release | [Store releases](development/releasing.md), [Android](development/android-release.md), [iOS](development/ios-release.md) |
| Configure App Check | [App Check setup and rollback](development/app-check.md) |
| Understand a past choice | [Decision records](decisions/) |

Architecture and feature status describe the current source. Decision records
explain choices at the time; a proposal or merged implementation is not evidence
of a production release. Historical UI requests are labelled as such.

When behavior changes, update its existing explanation. Link to detailed material
instead of repeating it. Changes to wire formats, keys, authentication or backend
rules need a decision record; check `main` and open pull requests for the next
free number before adding one.
