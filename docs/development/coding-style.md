# Writing code for Fireplace

These conventions describe work in this repository. Read [AGENTS.md](../../AGENTS.md) for the checks and contribution rules.

Use the pinned Dart formatter and keep the analyzer clean. Prefer clear names, single-quoted strings and package imports. Place related behavior together; separate a large screen's rendering from its state and service operations when that makes the code easier to review.

State exposed to widgets should be immutable. Represent an update with a new state value rather than changing a collection already held by a provider. Keep temporary mutation within the operation that owns it. Use types such as Duration, enums and small records where they explain a value better than a primitive or an unstructured map.

Widgets describe the screen and pass user intent to controllers or services. Give reusable UI pieces widget classes. Keep conditional children close to the layout they affect. Avoid placing persistence or network decisions inside rendering code.

An awaited operation can finish after navigation or sign-out. Check the relevant mounted state and account identity before applying its result. Cancel subscriptions and timers when their owner is disposed. Serialize writes that must have a defined order.

Treat message text and remote data as untrusted input. Validate at service boundaries, enforce size limits, and bound work that processes history or formatting. Keep expensive processing off the UI thread when necessary.

Errors shown in the app should explain what the user can do. Distinguish a definite refusal from an operation whose outcome is unknown. Preserve explicit confirmation for actions that might create a second message; never infer that a retry is safe.

Comments should explain a constraint or decision that the code cannot make obvious. A behavioral fix needs a regression test that reproduces the failure. Use fictional accounts and records, and keep tests independent of production credentials.

Protocol, key-handling and authentication changes require a design decision and tests. Reuse existing mechanisms and avoid adding packages or server data without an approved reason.
