# 0046: Hide recovery actions while reopening the account

Status: proposed after the v0.3.8 recovery flow.

A completed identity reset invalidates the app session. Riverpod's default
`AsyncValue.when` refresh behavior keeps displaying the previous error until
the new session finishes. If that error required recovery, the setup screen
and its identity-reset action remain visible and can be used again while
initialization is running. This makes a successful reset appear ineffective
and permits a second reset to race the first session startup.

AuthGate now displays the existing preparing-account splash on explicit
session refresh. Recovery/reset/retry actions disappear until initialization
returns data or a new actionable error. Dependency-driven reloads already
use this loading behavior. The existing session scope still owns cancellation
and resource cleanup; key generation, recovery, authentication, account
registrations and encrypted history formats are unchanged.

Widget regressions hold the restarted session pending after a recovery error
and a generic startup error. The preparing screen must replace the previous
error and its actions. Both fail without the change. Existing retry tests
still cover reaching the chat list without signing out. Steady screens and
their rendered layout remain unchanged.

There are no added reads, writes, server fields, network requests, dependencies
or permissions. Removing repeated reset actions during startup avoids issuing
unnecessary destructive operations. This does not reconstruct previously
deleted keys or guarantee recovery of unreadable messages.

Implementation assisted by OpenAI Codex.
