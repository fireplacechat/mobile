# 0024: Spam reports name the account and nothing else

Date: 2026-11-11. Status: accepted. Follows decision 0004, whose message-report
section is withdrawn.

Apple requires a way to report user-generated content. Fireplace cannot take a
message off someone else's device, so the only report is spam, from the
person's profile.

## What is stored

`reports/{reporterUid}_{reportedUid}`:

- `reporter`: the signed-in account
- `reported`: the other account
- `reason`: `spam`
- `createdAt`: server time

There is no message text, no note, and no chat id. The client method that
writes the document cannot attach a message. One report per pair; sending it
again replaces that document.

The Firestore rules already describe this collection. They must keep allowing
this shape and must not require message text. This repository does not deploy
rules.

## What the person sees

The chat header has the security-code shield only. Mute, Block and Report Spam
are on the profile, in that order. Block and Report Spam follow Signal's red
rows and Signal's bottom panels. Mute is the same row with a bell, in the
normal text colour. The report panel says Fireplace cannot see the chats.
