# Device readiness

A local device is ready only when its consistent local keys have a corresponding non-revoked server record. Missing registration routes to recovery/linking rather than silently reporting readiness or republishing keys. This also protects deliberate device removal.

Interrupted first-time publication is treated conservatively: there is no trustworthy local evidence distinguishing a never-published registration from one removed after publication. This change does not add a publication journal, mint replacement identities, or add server fields. Partial local key records are preserved and require explicit recovery. The existing recovery and linking paths install new certified devices deliberately.
