# 0030: Notification previews, decrypted on the phone

Status: requested by the owner (issue #82), 2026-11-12. Review before merge.
Goes with backend decision 0019 (the push payload). Android ships first, in
v0.3.6; iOS follows with a Notification Service Extension (#87). This note is
the design for all of it; each part lands as its own pull request with tests.

## What people see

A new setting, **Show message preview**, under Settings → Notifications. It is
on by default, stored on this device only (the server is never told), and
shown only on Android until iOS previews work.

| What arrived | Title | Body | Alert |
|---|---|---|---|
| a message | the sender's username, or "Fireplace" when "Show sender's name" is off | the text, shortened | yes |
| a reaction to one of my messages | the same | Reacted ❤️ to "start of the message…" | yes, as its own alert |
| an edit | | | no new alert; an alert still showing that message gets the new text, silently |
| a delete for everyone | | | removes the alert for that message if it is still showing |
| anything that cannot be decrypted in time | the same | New Message | yes |

With the setting off, notifications look exactly as they do now: the title,
"New Message", one alert per conversation. The server sends the same push
either way.

A conversation keeps one message alert (tag: the conversation key `k` of
backend decision 0013) and one reaction alert (tag `k` + `.r`), so a reaction
does not replace a message's alert. Alerts in the same conversation within
20 seconds of the last one update it silently, as the server's throttle
already limits pushes to one per 20 s.

## What Signal does, and what we copy

Read for this note: Signal-Android `gcm/FcmReceiveService.java`,
`FcmFetchManager.kt`, `FcmFetchForegroundService.kt`; Signal-Server
`push/FcmSender.java`; Signal-iOS `SignalNSE/NotificationService.swift` and
`NSEEnvironment.swift`.

- **Android.** Signal's server sends a high-priority FCM **data** message
  whose only content is the key `newMessageAlert`: no notification block, no
  sender, no text. `FcmReceiveService` starts a short foreground service and
  `FcmFetchManager` drains the message queue through the normal receive path.
  Signal's own notifier then posts the notifications from its database, so
  deletes and edits update what is showing. If the fetch does not finish in
  time it posts "You may have new messages". All of this is Signal's own
  native code; it uses no notification library.
  - **We copy:** a high-priority data-only push, the app's own receive path,
    the app posting its own notification, and the plain fallback ("New
    Message", the text we already show). Our notification code is our own
    native code too, in a small in-repo Flutter plugin (owner approved,
    2026-11-12; see "Native code" below).
  - **We differ:** Signal runs the fetch on the Java side of the same process
    that holds its database. Ours runs in a Dart background isolate that
    firebase_messaging starts in the app's process, next to the app's main
    isolate if it is alive. That is why the stores need a lock between
    isolates (below).
- **iOS.** The push carries `mutable-content`, so iOS starts Signal's
  Notification Service Extension, a separate process. It opens the same GRDB
  database in the app group (the keychain items are readable "after first
  unlock"), reloads its caches each time "to pick up changes made by the main
  app", fetches and processes messages, and posts notifications itself. If the
  keychain cannot be read (phone not yet unlocked since a restart) it posts one
  fixed notice. When time runs out it completes with empty content.
  - **We copy:** `mutable-content: 1` (already in backend 0019, harmless until
    the extension exists), the shared storage in an app group, reloading caches
    under a lock, and "after first unlock" for the keys (#85, below).
  - **We differ:** if the extension fails or runs out of time, iOS shows the
    push's own text, which is today's "New Message". Signal suppresses it with
    a special entitlement; we do not need that.

## The push (backend decision 0019)

- **Android, v0.3.6 and later:** a high-priority **data** message
  `{fp: "1", k, title, ch}`: the conversation key, the title the server shows
  today (the username, or "Fireplace" per `showName`) and the channel
  (`messages` or `messages_silent`, per `sound`). Google sees nothing it does
  not see today. No text, chat id, message path or envelope.
- **Which devices get it:** only registrations that say they handle it, with a
  new optional boolean `dataPush: true` on `users/{uid}/pushTokens/{deviceId}`.
  The app writes it from v0.3.6 on Android. Older apps have no background
  handler, so they keep the notification payload. Older apps rewrite the whole
  token document with `set()` at each launch, so a downgrade also falls back
  by itself.
  - The field says what the app can do, not what the person chose. A device
    with previews off still gets the data push and posts "New Message" itself,
    with the title and channel from the push.
  - **Rejected alternative:** notification plus data to everyone, the handler
    replacing the system's notification by the same tag. No rules change, but
    the system shows "New Message" first, the preview replaces it a moment
    later (a flicker, sometimes a second sound), and the two race.
- **iOS:** unchanged, plus `mutable-content: 1`.
- The throttle (one push per conversation per recipient every 20 s, a reaction
  counts) and who gets a push are unchanged.
- **Deploy order:** the backend rules must be live before v0.3.6 reaches
  anyone, or the new token field is refused and that device gets no pushes.

## What runs in the background (Android)

firebase_messaging hands a data message to a top-level
`@pragma('vm:entry-point')` handler in a second Dart isolate when the app is
not in the foreground. In the foreground it goes to `onMessage` in the app's
isolate, where the in-app notice already shows arrivals, so nothing is posted
there.

1. Ignore anything without `fp`. Read the signed-in user from FirebaseAuth's
   saved session; none means "New Message".
2. If previews are off on this device (or the person turned notifications off
   in Fireplace), post "New Message" with the push's title and channel, and
   stop. No fetch, no extra reads: exactly today's behaviour.
3. Find the chat: hash each chat id in this device's list of live chats (kept
   by the app in the secure store; the chats it already syncs) the same way the
   server does, and take the match. No match means "New Message".
4. Initialise Firebase and App Check, open the stores **read-only for keys**
   (load the device, never create one; open history only if its key exists),
   take the account lock, and run the existing receive code once for that chat
   only: one Firestore query from the saved cursor, each new message through
   the same `_process` as the app (authorisation, journal, history, session).
5. Post what arrived (the table above). If the fetch fails, a message is
   deferred (for example an identity change waiting for the person), or the
   whole run passes its time limit (8 s), post "New Message".
6. Close everything.

**Never in the background:** sending, publishing, prekey upkeep (refills and
the repair after an unknown prekey), confirming sends, writing chat state to
the server, or anything that advances a sending chain beyond what receiving
itself does. The one server write left is the one receiving already makes:
deleting the public copy of a one-time prekey a new session used.

**When the app is alive in the background** its own listeners may receive the
message first. Then the app posts the notification for what it received
(previews and notifications on, and the app not in the foreground), and the
background run finds nothing new and posts nothing. Whichever gets the message
first posts it; the other skips it. This also gives an alert for messages
inside the server's 20-second throttle while the app is alive, which update the
conversation's alert silently.

## Exactly once into history

Within one isolate this already holds: every receive runs under one lock,
`has()` skips a message already in history, and the receive journal finishes
anything half applied before the next message (decisions 0007 and 0013). The
background run uses the same code and the same stores, so it holds across
isolates as long as both take the **same lock** and **neither trusts a cache
the other may have outdated**:

- **The account lock** (`SharedLock`, `lib/src/db/shared_lock.dart`), taken around
  every session change, every history write, the receive cursor and every
  change to the private prekeys. It is re-entrant within one call chain (a
  receive saves history and consumes a prekey while holding it).
  - *Between isolates in one process* (Android): `IsolateNameServer` from
    `dart:ui`. Registering a port under the account's lock name is an atomic
    test-and-set; releasing removes the name. A waiter pings the holder's port;
    a holder that does not answer twice within 2 s is gone (its engine was
    destroyed) and its name is removed. A live isolate answers pings while it
    awaits the network, so only a dead one is reclaimed.
  - *Between processes* (iOS, the app and the extension): a file lock
    (`RandomAccessFile.lock`) on a file in the app group. Added with the iOS
    extension, not now: POSIX locks are per process, so two isolates of one
    process do not exclude each other, and closing any handle to the file
    releases the process's lock. On Android, where everything is one process,
    it would add nothing and could release a lock by mistake.
- **The generation counter**, a small file next to the history (`lock.gen`).
  Whoever holds the lock reads it on taking the lock and writes it one higher
  on releasing. If it changed since this isolate last held the lock, someone
  else wrote: this isolate drops its `CachedSecretStore` values and its
  history cache (`EncryptedFileMessageStore`) before doing anything, and
  re-emits the chats the app is watching, so messages saved in the background
  appear in an open chat. Reads outside the lock (the chat screen, the cursor
  when a listener starts) may briefly see older data, which is harmless: every
  decision that matters (`has()`, sessions, the journal) is made under the
  lock.
- The app takes the lock at the same points as today's `AsyncMutex`, so
  nothing new waits in normal use. A background run holds it for at most its
  time limit; an app starting meanwhile waits for it.

The randomized chat simulation gets a mode with two `ChatService`s over the
same underlying stores, each with its own caches and its own lock instance,
receiving the same chat in random interleavings, with failures injected. It
asserts what it already asserts (no message lost, none twice, none decrypted
twice, the conversation not stuck) plus that no session goes back to an older
state.

## What a notification may contain

The text is decrypted in memory and handed to the system to show; that is the
only place plaintext goes. Nothing new is written to disk in clear: history is
encrypted as before, and the notification's extras hold only the message id
(to remove or update the right alert later). The person can hide alert content
on the lock screen in Android's own settings, as today. Bodies are cut to
1,000 characters before posting, and a reaction quotes at most the first
40 characters of the message, so the work stays bounded.

## Keys on a locked iPhone (#85), decided

**Decision (owner, 2026-11-12):** the keys the extension needs move to "after
first unlock" (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), as Signal
uses, so previews work on a locked phone. **Applied only with the iOS
extension (#87)**, with a migration of existing keychain items and tests.
v0.3.6 changes nothing about keychain accessibility (decision 0018 stands).

The trade-off, for the record: from the first unlock after a restart until the
next restart, the keys can be read by the app even while the phone is locked.
Someone who takes a phone in that state and can attack it while locked faces a
weaker barrier than today. A phone that was turned off, or restarted and not
yet unlocked, is as protected as now.

- Still open, low priority: for everyone, or only while "Show message preview"
  is on. Recommendation: only while it is on. To be asked when the iOS work
  starts.
- It fits the optional passphrase lock (#77, modelled on the Molly fork of
  Signal) and the encrypted database (#78). "After first unlock" is the default
  protection. With the passphrase lock on, the keys are wrapped with
  Argon2id(passphrase) and wiped from memory when the app locks, so even on an
  unlocked-once phone nothing can be read until the passphrase is entered, and
  notifications show "New Message" while the app is locked, as Molly does.
  #77 and #78 are not part of v0.3.6.

## Native code

An in-repo Flutter plugin, `packages/fireplace_native/` (a path dependency, our
own Kotlin, no third-party code, nothing that phones home). A plugin is
registered in every Flutter engine, including the one firebase_messaging
starts for the background handler; MainActivity's own method channel exists
only in the app's engine. It creates the notification channels if they are
missing, posts, updates and removes Fireplace's notifications, and lists the
ones showing. Swift joins it with the iOS extension.

## What it costs

- **Per push to an Android device on v0.3.6 with previews on:** one Firestore
  query on that chat's messages from the saved cursor, so one read per new
  message document, and one read when there is nothing new (the app got it
  first). Usually 1 to 3 reads. When the app is alive its own listener has
  read the message already, so the background run adds about one read.
- **Previews off:** no reads; the same as today.
- **New sessions** read the sender's device keys, as receiving already does.
- **Server:** the push function's reads and writes are unchanged (backend
  0019). The token document gains one field; no extra writes.
- At 20 people × 100 messages a day that is at most about 2,000 extra reads a
  day, inside the free 50,000. FCM is free.

## Order of work and tests

1. This note.
2. Backend #22: the data payload, `mutable-content`, the `dataPush` field in
   the rules. Tests: both payload shapes, `showName` and `sound` unchanged,
   the throttle unchanged, no text, chat id or envelope in any payload; rules
   tests for the field.
3. #88: the setting and the formats as pure functions in
   `lib/src/model/notifications/`. Tests for each format, the tags, the
   default, persistence, and the settings row on Android only; render cases.
4. #84 and #17: the account lock, the generation counter, cache invalidation,
   `AsyncMutex` tests, and the simulation with two services.
5. #86: the plugin, the background handler, the app posting while in the
   background, `dataPush` on the registration. Tests with fake Firestore and
   the real receive path, the time-limit fallback, nothing posted twice when
   the app is also running, and `scripts/check_apk.sh`.
6. #85: this decision, also recorded on the issue.
7. #87: the spike plan on the issue (a headless Dart engine in the extension
   against its 24 MB limit, or a Swift port with every protocol test vector
   run against both).

## As built for Android (v0.3.6)

- `lib/src/app/background_push_entry.dart`: the `@pragma('vm:entry-point')`
  handler, registered in `main.dart` on Android. It sets up Firebase and App
  Check as the app does (`firebase_setup.dart`), answers push challenges
  (backend 0020) and hands Fireplace pushes to `BackgroundPush`
  (`lib/src/model/push/background_push.dart`).
- The app keeps the list of chats it receives in `pushchats:<uid>` in the
  secure store (`PushChatIndex`), written only when it changes.
- Stores open without creating anything: `KeyService.existingDevice` and
  `EncryptedFileMessageStore.open(createKey: false)`.
- `PreviewNotifier` applies the formats; `ArrivalNotifier` posts from the app
  while it is alive but not on screen, and only with previews on, so the plain
  alert of a push with previews off never sounds twice.
- `packages/fireplace_native` (Kotlin) creates the channels in every engine
  (MainActivity no longer does), posts with a lock-screen version that shows
  "New Message" when the person hides sensitive content, keeps the message id
  in the alert's extras, and updates an alert posted under the same tag in the
  last 20 seconds silently, whichever isolate posted it.
- The registration carries `dataPush: true` on Android.

Follow-ups, not in v0.3.6: a separate "Reactions" channel so reactions can be
silenced on their own, and honouring a chat's mute in the system alert now
that the device decides what to show.

Implementation assisted by Claude Code.
