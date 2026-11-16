# 0064: A person's colour is followed while their chat is open

Date: 2026-11-16. Status: proposed for review. Changes one line of
[0053](0053-colour-on-the-profile.md), "How it is written and read".

## Problem

A colour changed in Settings showed at once in group chats, where it travels
as a message, and in a 1:1 chat only after the other person restarted the app
(issue 193). 0053 read a chat partner's profile when their chat was opened,
and only if it had last been read more than 15 minutes before. A chat that
was already open, or opened again within those minutes, kept the old colour.

## Decision

While a 1:1 chat is open, the app listens to the other person's profile
document. A change of their colour shows in the conversation, and from there
in the chat list and in chat details, without leaving the screen. The
listener ends when the chat closes.

The chat list does not listen: a person whose chat is not open is read once
after the app opens, with their name, as before.

## Cost

One document read each time a 1:1 chat is opened (before: at most one per
person per 15 minutes), and one for each change of that person's profile
while it is open. A profile changes when its owner changes their colour,
which the server limits to once in 5 seconds, so a chat left open costs
nothing while nothing changes. No writes, and nothing new on the server.

## Validation

- Model: with a chat open, two changes moments apart both arrive, though the
  profile was read seconds before; after the chat closes nothing more is
  followed; following one's own profile notes nothing.
- Screen: opening a chat starts following that person, and closing it stops.
