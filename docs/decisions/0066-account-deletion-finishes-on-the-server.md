# 0066: Account deletion finishes on the server

Status: proposed. Backend side: backend decision 0028. Issue 119.

## Problem

The app deleted an account with about ten requests through the rules (decision
0048). A dropped connection anywhere left a half-deleted account behind its
`deleting` fence, and the person had to tap "Try again". On the emulator, two
of three in-app deletions of one account stopped that way, one of them because
Firestore resent a delete that had already worked and the rules refused it
(fixed for the app's own steps in #231).

Signal deletes an account with one authenticated request and wipes the app;
WhatsApp ends access at once and finishes on its servers. The work sits where
repeating it is always safe.

## Decision

The phone keeps what only it can do, then asks the server for the rest:

1. reauthenticate; set `deleting: true`; stop the session and freeze this
   account's preferences (unchanged);
2. erase this account's local history, settings and keychain entries (moved up
   from after the server deletes; still before the profile and username go, so
   a failed erase keeps the fence and can be resumed with the password);
3. write `deletionRequests/{uid}` with `at` (server time) and wait: the server
   marks it `startedAt`, deletes the account's records and sign-in account,
   then the request. A server snapshot without the request means done;
4. sign out.

The app does the rest itself, exactly as before (with #231's read-back), when
the server does not take the request: the write is refused (an older backend)
or does not reach the server within 15 s (offline), nobody marks it within
15 s, or it is not done within 60 s. A refused write while an earlier request
is still there waits for that one. Both ways can overlap, since every step can
run again on either side; a sign-in account the server already removed counts
as deleted.

Offline, the request may still reach the server later, and the server then
finishes the deletion although the phone showed "Deletion did not finish".
That is what the person asked for, and "Try again" then completes at once.

## Wire and rules

New document `deletionRequests/{uid}`: `{at}` written by the owner behind the
fence within five minutes of typing the password; `startedAt` written only by
the server. Readable by its owner. No other change; older apps are unaffected.

## Cost

One request write and one listen per deletion (two or three reads), one
function call, and the same document deletes as before, now from the server.
The fallback adds nothing when it does not run.

## Tests

`test/model/account/server_deletion_test.dart`: the server path (steps, no
sign-in deletion by the app, everything gone, the phone erased before asking),
an older server, a server that takes it but does not finish, offline, and an
earlier request still being worked on. The existing deletion tests run the
fallback. Backend: rules and function tests in backend decision 0028; checked
end to end on the Android emulator with the functions emulator.
