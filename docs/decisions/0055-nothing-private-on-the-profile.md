# 0055: Nothing private on the public profile

Date: 2026-11-15. Status: accepted by the owner. Closes issue 179. The matching
rule change is made in the backend and is live.

## The problem

A profile (`users/{uid}`) is readable by every signed-in account: names and
colours are read from it. It also carried:

- `lastActiveAt`: when the account was last in use, refreshed about every 13
  hours so that an account in use is never deleted for inactivity. Anyone who
  knew an account's id could read it with a modified app. That is a "last seen",
  which this project rules out.
- `invite`: the hash of the invite the account joined with.

## What changes

- **The app no longer writes `lastActiveAt`.** Inactivity is judged on the
  server from the sign-in account's own record of its last sign-in and last
  token refresh, which an app in use renews about hourly and which no other
  account can read.
- **The app removes both fields from its own profile** when it finds one there:
  the invite hash right after sign-up, and a stamp left by an older version. One
  write, once.
- The server refuses a new stamp, and existing profiles have been cleaned.

## What other people can still read

Username, display name, colour, and the date the account was created.

## Older versions

A version before this one still tries to write the stamp. The server refuses it,
and that version already ignores the refusal. Its invite hash stays on its
profile until it updates.

## Cost

One write fewer per account about every 13 hours. One write, once, to remove
the fields.

## Tests

`test/model/account/profile_privacy_test.dart`. The server's side is tested in
the backend.
