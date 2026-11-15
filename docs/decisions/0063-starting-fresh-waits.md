# 0063: Starting fresh on a new phone waits, and the owner can stop it

Date: 2026-11-15. Status: proposed for review.

## Problem

An account is a username and a password. Someone who has both, and no device
of the account, can sign in on a new phone and choose "start fresh": a new
identity, and every device of the account removed. That is how a person gets
back in after losing their only phone. It is also how someone who learned the
password takes the account. Contacts see a security code change, and nothing
else stands in the way.

Asking for a second secret (a PIN, the recovery key) would close this, and
would lock out everyone who lost their phone and forgot the second secret.
The app should ask people to remember nothing new.

## Decision

A person has two things: a phone that is on the account, and the password.
Someone who stole the phone has the first. Someone who learned the password
has the second. Only the person has both.

1. **Starting fresh waits.** When the account has a device, "start fresh" on a
   new phone does not happen at once. It is recorded, and it happens when the
   account's waiting time has passed. Three days unless the person chose
   otherwise.
2. **Every device of the account says so.** While a start is waiting, each
   device shows it, over everything else, and is sent a notification.
3. **A device can stop it, with the password.** "Stop them" asks for the
   password, cancels the waiting start, and has the person choose a new
   password, since someone else knows the old one.
4. **Otherwise it goes ahead.** When the time has passed, the new phone
   finishes starting fresh.

Who wins:

| | Has | Result |
|---|---|---|
| Learned the password | no phone | The person's phone tells them; they stop it and change the password. |
| Stole the phone | no password | The person starts fresh on a new phone. The thief sees it and cannot stop it. After the wait the stolen phone is out. |
| The person, phone lost | password | Waits, then is back in. |
| The person, phone in hand | both | Links the new phone by scanning; no wait. |

Someone with both the phone and the password is the person, as far as any
system can tell.

No wait applies when the account has no device at all (a first sign-in, or
after every device was removed), or when the person has the recovery key or
another device: those paths keep the identity and are unchanged.

## The waiting time

Chosen by the person: 1, 3, 7, 14 or 30 days. Three days is the default and
what existing accounts get.

- At sign-up it is one row on the form, already set to three days.
- Later it is in Settings, under Devices and recovery.

Changing it needs a device of the account. A session that has only the
password cannot change it, or it would set it to the shortest and wait that
out.

## What must be true on the server

The app cannot enforce any of this: someone with the password can talk to the
server with their own program. So the server decides, and it must be able to
tell a device of the account from a session that only has the password.

- **Proof of a device.** A request that only a device may make carries a
  proof made with that device's long-term X25519 key: a MAC, keyed by the
  shared secret between the device key and a key of the server, over the
  account, the device, the request and its id. The server checks it against
  the device's published key. No new device key and no migration: every
  device already has the key. The shared secret is used only through HKDF
  with its own label, and a non-contributory secret is refused, as in 0020.
- **Only a device may**: remove a device, replace the identity at once (0062),
  change the waiting time, stop a waiting start.
- **Stopping also needs the password**, entered again just then: the server
  accepts it only from a sign-in a few minutes old. A stolen phone has an old
  sign-in and no password.
- **Anyone signed in may**: ask to start fresh, and withdraw their own asking.
  The server records when. Removing the account's devices and publishing a
  device under a new identity are refused until that time plus the waiting
  time has passed.

The server's rules and functions for this are the owner's to deploy. The app
change is inert until they are.

## Screens

Few words; the app's sheet for questions.

- **New phone, start fresh.** One confirmation, then a screen that says when:
  "Ready on Thursday" and one line, "Your other devices can stop this.", with
  Cancel.
- **A device of the account**, over everything: "A new phone is taking over
  your account" and one line with the day, with two buttons, "Stop them" and
  "It's me". "It's me" puts the notice away and changes nothing. "Stop them"
  asks for the password, then for a new one.
- **Settings.** One row, "Lost-phone wait", showing the time; it opens the
  sheet with the five choices.
- **Sign-up.** The same row on the form.

## Costs

One listener per signed-in device on one document (the waiting start, usually
absent). One function run per device request and one notification per device
when a start begins. Nothing recurring.

## Limits

- The person must notice within the waiting time. A longer wait gives more
  time to notice and makes a real loss slower to recover from; that is the
  choice the setting offers.
- Someone with the password can still sign in. They can ask to start fresh
  again after being stopped, until the password is changed; stopping changes
  it for that reason.
- A stolen phone that is unlocked can read what is on it until the wait ends.
  The lost-device reset from another device of the account (0062) is
  immediate.
- If the person lost the phone and someone else also knows the password, the
  two are indistinguishable.
- Deleting the account with only the password is not covered here.
