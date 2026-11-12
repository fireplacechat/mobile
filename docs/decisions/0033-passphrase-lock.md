# 0033: Optional passphrase lock

Status: Proposed, for the owner to decide. Issue #77. No code in this change.
The direction is the one in decision 0030, under "Keys on a locked iPhone":
an optional lock modelled on Molly, on top of "after first unlock".

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

## What we copy

- Off unless the person turns it on. Decision 0018 stays for everyone else.
- Argon2id from `cryptography` 2.9.0, which the app already depends on. No new
  package. That package's `memory` is a count of 1 KiB blocks, so a byte count
  from Molly is divided by 1024.
- Measure once, on the phone, when the passphrase is set. Store the parameters.
  Unlock reuses them. Floor of 4 iterations, and do not go under Argon2's
  minimum memory. Do not ask for more than about half the free memory.
- Mix the result with a non-exportable key in the iPhone Keychain and the
  Android Keystore, the same job as Molly's keystore HMAC.
- A wrong passphrase changes nothing. There is no recovery.
- While the app is locked, a notification is "New Message" only (decision 0030).

## What is different

History here is AES-GCM files (decisions 0013 and 0027), not a SQLCipher
database. The secret that hides history is `msgkey:<uid>`. Molly's database
key is not under the passphrase; ours has to be, or the lock does not hide
messages.

We do not kill the process and we do not overwrite all free RAM. Dart does not
give us that. We wipe the passphrase bytes and the unwrapped keys we hold, and
we drop the in-memory copies. A native wipe of free RAM can be a later decision.

"After first unlock" (decision 0030, issue #85) stays the default, so previews
work for people who do not set a passphrase.

## What is wrapped

- `msgkey:<uid>`, the history key
- `chatprefskey:<uid>`, mute, pins and read marks (chat ids, not message text)
- `identity:<uid>`, this account's private identity
- `sess:<device>:<peer>:<peerDevice>`, the sessions
- `journal:<device>`, an open receive journal

## What stays readable

The signed-in uid, the salt, the Argon2 parameters, the wrapped blobs, and the
push registration. Nothing that decrypts a message, a name, or a session. A
locked app can post "New Message". It cannot show a preview or the chat list.

## Unlock, lock, change, and a forgotten passphrase

Unlock runs Argon2 on a background isolate, then unwraps. It takes about 3
seconds and does not use the network.

Lock is a button, a timeout after unlock, and leaving the app. The unwrapped
keys are dropped.

Changing it unwraps with the old passphrase and writes a new wrapped blob, then
removes the old one. A crash in between still opens with the old passphrase
(decision 0013).

A forgotten passphrase cannot be reset. This device's history, sessions and
identity secret are gone. The account on the server is still there. This device
has to be set up again. The screen says that, in those words, before the
passphrase is accepted.

## How it fits #85 and #86

Issue #85 moves keychain items to after first unlock only with the iOS
extension, and only so previews can run on a locked phone. This lock is
optional. With it on, those items are wrapped, and they are not in memory, so
after-first-unlock does not reveal them.

Issue #86, while this lock is on and the app is locked, does not decrypt and
does not open history. It posts "New Message" only.

## Parameters

Cited from Molly's `PassphraseBasedKdf`. Not measured on a Fireplace phone yet.

- Argon2id, version 0x13
- about 3 seconds, once, on the phone where the passphrase is created
- at least 4 iterations
- memory starts at 16383 bytes times the parallelism, then rises until the hash
  takes about 3 seconds, and stops at about half the free memory
- parallelism is one less than the CPU count, or 1
- 16-byte salt, 32-byte output

The first code change measures one older phone and adds the numbers it picked
here before that code merges.

## Cost

One local Argon2 run each time the person unlocks, and one when they set or
change the passphrase. No Firestore read or write. Only people who turn it on
pay it.

## Tests it will need

- a wrong passphrase does not unwrap, and the failure does not throw out
- the right passphrase unwraps, and after lock the history key is gone from memory
- the stored parameters are reused, not measured again on unlock
- after a change, the old passphrase fails and the new one works
- a crash before the old blob is removed still opens with the old passphrase
- nothing unwraps with an empty passphrase or a skipped prompt
- while locked, the #86 path is not given the history key, and the text is
  "New Message"
- the derivation test is tagged `timing`

## Order of work

1. This note. The owner decides.
2. Wrap and unwrap the keys above. Tests. No screen.
3. Lock and unlock: the button, the timeout, and leaving the app.
4. The screen for setting and changing it, including the warning that a
   forgotten passphrase deletes local history on this device. Renders.
5. #86 checks the lock.
6. Measure an older phone and record the Argon2 numbers in this note.

Drafted by Grok.
