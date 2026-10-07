# Documentation

| Folder | Contents |
|---|---|
| [architecture.md](architecture.md) | feature layout, dependencies and remaining extraction steps |
| [development/](development/) | set up, coding style, CI, Android release notes, optional stricter lint config |
| [development/app-check.md](development/app-check.md) | App Check monitoring, setup and rollback |
| [development/ios-release.md](development/ios-release.md) | owner checklist for protected iOS signing and TestFlight |
| [development/releasing.md](development/releasing.md) | draft releases and locally signed store bundles |
| [protocol/](protocol/) | threat model, crypto evaluation notes, account deletion |
| [decisions/](decisions/) | numbered design decisions (0001 onward): why each choice was made |
| [decisions/0017-app-check.md](decisions/0017-app-check.md) | monitoring-only app attestation decision |
| [roadmap/](roadmap/) | planned features and the feature matrix |
| [assets/](assets/) | images used by the documentation |

New decisions go in `decisions/` as the next number, written when the change is made. Anything that changes a wire format, key handling, authentication or the backend rules needs one.
