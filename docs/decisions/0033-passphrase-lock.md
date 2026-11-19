# 0033: Optional passphrase lock

Status: accepted by the owner on 2026-11-19, with the four choices recorded
under *Owner's choices*. Issue #77. First drafted before history moved into
SQLCipher (0057) and the keychain was shared with the iPhone notification
extension (0042, 0043); this version is updated for both. The direction is the
one in decision 0030, under "Keys on a locked iPhone": an optional lock
modelled on Molly, on top of "after first unlock".

## What Molly does

Read from Molly's current Android source, not from its older wiki.

`PassphraseBasedKdf` runs Argon2id (version 0x13). It aims for about 3 seconds
on the phone where the passphrase is created. The floor is 4 iterations and
16383 bytes of memory, multiplied by the parallelism. Parallelism is one less
than the number of CPUs, or 1. The cap is half the memory free at that moment.
The chosen parameters are stored and reused. The salt is 16 bytes. The
passphrase bytes are wiped after the hash.

The hash is then passed through HMAC-SHA256 with a key that stays in the
Android keystore (StrongBox when the phone has it). That device key is not
exported. A copy of the app's files, without the phone, cannot be searched
for the passphrase. If that keystore key is lost, the passphrase does not
open the data.

The result wraps two random secrets, a 32-byte AES key and a 32-byte MAC key,
with AES-GCM. Those secrets encrypt the local identity key. A wrong passphrase
fails the AES-GCM check. Changing the passphrase unwraps with the old one,
picks a new salt, new parameters and a new keystore key, and wraps again.

The database key is a separate 32-byte random value, sealed in the keystore
(`DatabaseSecretProvider`). Today's Molly does not put that database key under
the passphrase.

On lock, Molly drops the keys it was holding, can exit the process, and
`WipeMemoryService` overwrites free RAM so a memory image is less use.

## Owner's choices (2026-11-19)

1. **No notification previews while the lock is on**, on either platform, even
   while the app is unlocked. Every alert is "New Message".
2. **The device key is a random secret in the existing secure store**, not a
   new non-exportable key. No native code.
3. **Auto-lock is the person's choice**, five minutes away by default.
4. **A forgotten passphrase offers "Erase and set up again"** on the unlock
   screen.

## What we copy

- Off unless the person turns it on. Decision 0018 stays for everyone else.
- Argon2id from `cryptography`, which the app already depends on. No new
  package. Its `memory` is a count of 1 KiB blocks.
- Measured once, on the phone, when the passphrase is set. The parameters are
  stored, and unlocking reuses them.
- The passphrase's hash is mixed with a device secret (choice 2), the same job
  as Molly's keystore HMAC.
- A random data key is wrapped with the result. Changing the passphrase
  rewraps only that key.
- A wrong passphrase changes nothing, and there is no recovery (choice 4).

## What is different from Molly

**The history database key is under the passphrase.** Molly's database key is
not. Ours is `msgkey:{uid}`, the SQLCipher key of `history.db` (0057). If it
were left out, the lock would not hide messages.

**The device secret is not hardware-bound** (choice 2). It is a random 32-byte
value, `passlockpepper:{uid}`, in the same Keychain / Keystore-backed store as
everything else, device-only and never in a backup. Without it, a copy of the
app's files gives nothing. Someone who extracts both the files and the secure
store can try passphrases offline, at the cost of an Argon2id run per guess. A
non-exportable key would stop that, and can be added later without changing
the stored format.

**We do not kill the process or overwrite free RAM.** Dart does not give us
that. On lock the account's session is closed, which drops its in-memory
copies (the secure-store cache, open sessions, the database connection), and
the data key is forgotten. Dart strings cannot be wiped, so a copy may stay in
freed memory until it is reused.

## What is wrapped

Each of these is stored as `fpl1:` followed by AES-256-GCM of its value under
the data key, with the item's name as associated data, so a value cannot be
moved to another name:

- `msgkey:{uid}`, the history database key (and the old per-chat files')
- `chatprefskey:{uid}`, mute, pins and read marks
- `groupkey:{uid}`, the group records' key
- `identity:{uid}`, this account's private identity
- `device:{uid}`, this device's private keys
- `prekeys:{uid}:{device}`, the private halves of the prekeys
- `sess:{device}:…`, the sessions
- `journal:{device}`, `journals:{device}` and `journal:{device}:…`, an open
  receive journal

## What stays readable

`passlock:{uid}` (the salt, the Argon2 parameters, the wrapped data key, the
device id, the auto-lock choice and the preview choice to restore),
`passlockpepper:{uid}`, the signed-in uid, the public `bundle:{uid}`, pinned
identities (public keys), receive cursors (times), peer colours, the lists of
hidden and cleared chats and the push chat index (chat ids), and the push
choices. Nothing that decrypts a message, a session or a name.

## Previews (choice 1)

Both background paths already post a plain "New Message" when
`pushnopreview:{uid}` is set: the Android handler (decision 0030) and the
iPhone extension (0043), which checks it before touching anything else. Turning
the lock on remembers whether previews were on, in `passlock:{uid}`, and sets
that marker. Turning it off puts the person's choice back. "Show message
preview" in Settings is shown off and disabled meanwhile, with the reason. No
change to the extension.

With previews off, the Android handler does not open the stores, and the
extension never reads a wrapped item. A message that arrives while the app is
locked waits on the server and is received after unlock, as one does today
when the app is closed with previews off.

## Unlock, lock, change and turning it off

**Unlock** runs Argon2id on a background isolate, mixes in the device secret
(HMAC-SHA256), and opens the data key with AES-GCM. A wrong passphrase fails
that check and changes nothing. It does not use the network.

**Lock** happens on "Lock now", on restart, and when the app comes back after
being away for the chosen time: immediately, 1 minute, 5 minutes (default),
1 hour or 1 day (choice 3). The session is closed first, so writes in flight
finish, then the data key is dropped and the unlock screen shows.

**Turning it on** writes `passlock:{uid}` with `pending: on`, then rewrites each
item above wrapped, then clears `pending`. **Turning it off** sets
`pending: off`, rewrites each item plain, then removes `passlock:{uid}` and the
device secret. Reads accept both forms while either is under way. If the app
is stopped half-way, the record is still there: the next start asks for the
passphrase and finishes the job.

**Changing it** needs the old passphrase. A new salt and parameters wrap the
same data key, written in one secure-store write. The items are not touched.

## A forgotten passphrase (choice 4)

It cannot be reset. The unlock screen offers "Erase and set up again", after a
warning. It erases this account's data on this phone (history, keys, sessions,
preferences) and signs out. The account on the server stays. Signing in again
is like a new phone: restore with the recovery key, link from another device,
or start fresh (0063). The screen that turns the lock on says this before the
passphrase is accepted.

## Parameters

Argon2id, version 0x13, parallelism 1, a 16-byte salt and a 32-byte output.
Measured when the passphrase is set: start at 19 MiB and 2 passes (the OWASP
minimum) and double the memory while one run takes under about 0.4 seconds, up
to 64 MiB; then raise the passes while a run takes under about 1 second, up to
8. The chosen numbers are stored. Unlock reuses them, so it takes about 1 to 2
seconds.

`cryptography`'s Argon2id is pure Dart. On a 2026 laptop (JIT, in a test), one
run took 180 ms at 19 MiB and 2 passes, 250 ms at 32 MiB and 3, and 600 ms at
64 MiB and 3. A phone in release mode is not measured yet; the first build
records an older phone's numbers here.

Molly aims for 3 seconds and up to half the free memory. We aim lower and cap
memory at 64 MiB, because Dart cannot ask how much memory is free, and the
calculation runs while the app is in use.

## Cost

One Argon2id run on each unlock, and when the passphrase is set or changed.
No Firestore read or write. Only people who turn it on pay it.

## Tests it will need

- a wrong passphrase does not open the data key, and the failure is shown in
  plain words, not as an exception
- the right passphrase opens it; after lock, wrapped items cannot be read and
  the session is closed
- the stored parameters are reused on unlock, not measured again
- after a change, the old passphrase fails and the new one works, and the
  items are untouched
- turning it on and off with existing history, sessions and groups, including
  stopped at every step, loses nothing and finishes on the next unlock
- a wrapped value moved to another name does not open
- previews are off while it is on, and the earlier choice comes back
- "Erase and set up again" erases this account's data on this phone only
- the derivation test is tagged `timing`

## Order of work

1. This note.
2. The wrapping store, the lock record, turning it on, off and changing it,
   unlocking and locking. Tests. No screen.
3. The unlock screen, auto-lock, Settings and "Erase and set up again".
   Previews forced off. Renders.
4. Measure an older phone and record the Argon2 numbers here.

Drafted by Grok; updated for 0042, 0043 and 0057 by Claude.
