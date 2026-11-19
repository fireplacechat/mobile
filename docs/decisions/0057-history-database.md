# 0057: History in an encrypted database

Date: 2026-11-15. Status: accepted by the owner ("SQLite, with SQLCipher").
Tracks issues 181, 180 and 78. Adds one package. This note covers the whole
move; the first change builds the store and does not switch the app to it.

## Why

History is one encrypted file per chat, and a file can only be read whole.

- At start the app decrypts every chat's entire history, to show each chat's
  last message and unread count. Measured: about one second per 10,000 messages
  on a PC, more on a phone.
- Every new message re-sorts and re-copies the chat's whole history for each
  listener.
- "Seen" is a list of every message id ever seen, rewritten in full each time.
- The format, its crash recovery and its search are our own code to maintain.

The usual design for a messenger is an SQLite database, encrypted with
SQLCipher, that loads a screenful and fetches older messages on scrolling.

## Decisions

- **SQLite, encrypted with SQLCipher.** The whole database file is encrypted,
  with the account's existing history key (`msgkey:{uid}`, 32 random bytes in the
  Keychain / Keystore) used as a raw key.
- **Package: `sqlite3`** (pub.dev, publisher simonbinder.eu, MIT), approved by the
  owner. Its build hook downloads the prebuilt SQLCipher library for each
  platform and checks it against hashes shipped inside the package. Configured
  in `pubspec.yaml` (`hooks: user_defines: sqlite3: source: sqlcipher`).
  SQLCipher is under a BSD-style licence and links OpenSSL on Android.
- **No object mapper.** The schema is small; plain SQL keeps what must be
  reviewed small.
- **One database per account**, `history.db`, next to where the files were.
- **The iPhone notification extension does not open the database.** A reaction
  alert there reads "Reacted 👍 to a message", without the quote (owner's
  choice). The extension stays small and inside its memory limit.

## Schema, version 1

One table, `messages`: arrival number, chat, id, send time, whether it is shown
in the conversation, whether this account sent it, the message it changes (for
an edit, a reaction or a delete), the message it quotes, a read flag, and the
whole record as JSON. Indexes: by chat and time; by changed message; by quoted
message; unread.

The record stays JSON for now, so the meaning of every field is exactly what it
was. Columns exist for what is searched or sorted.

## Same behaviour

What an edit, a reaction, a delete and a quote do is decided by one function,
the projection, as before. The file store ran it over the whole conversation on
every change. The database store runs it over the few records a change can
affect: the message, the edits, reactions and deletes aimed at it, and the
messages that quote it.

A test applies random sequences of every operation to the database store and to
the reference store and compares everything observable (24 seeds, 220
operations each).

One deliberate difference: messages with the same send time are ordered by
arrival. The reference left their order undefined.

One limit: relations are followed one step. An edit aimed at another edit means
nothing and is not followed; the app never sends one.

## Deletion

Erased text must not stay on the device (decision 0023).

- `secure_delete` is on: SQLite overwrites the space a deletion frees.
- After any change that erases content, the write-ahead log, which still holds
  the pages as they were, is emptied.
- Tests: the settings are on; a deleted row's bytes are gone from an unencrypted
  file with the setting on and present with it off; after every kind of deletion
  the decrypted database contains none of the deleted text.

## Durability

A change is one transaction, written with `synchronous = FULL`, and readers see
it only after it is saved. A message's ratchet key is spent when it is
decrypted, so the message must be on disk before the app goes on (decision
0013).

## Order of work

1. **The store, tested, not yet used.** (This change.)
2. **Import and switch.** Each chat's file is imported once, in a transaction;
   the files are removed only after the import is saved, so an interrupted
   import starts again. The background push handler opens its own connection.
3. **Read flags, summaries and pages** (issues 180 and 181): unread becomes an
   indexed count, the chat list reads one row per chat, a conversation loads its
   newest messages and fetches older ones on scrolling up.
4. **Search** in the database.
5. **Sessions, receive journal and cursors** move in, written in the same
   transaction as the message. This changes the protocol's crash safety and is
   its own decision: 0065 proposes not doing it.

## The switch (step 2)

- **Import, chat by chat.** A history file's name is a hash of its chat id and
  its contents are sealed to that id, so files cannot be listed and imported in
  one go. Each chat's file is imported the first time the chat is used: read,
  watched, written or deleted. In practice that is every chat, when the app
  opens.
- **Safe to interrupt.** The file goes into the database in one transaction,
  with a row saying so; the file is removed only after that is saved. Stopped
  before: the import starts again from an untouched file. Stopped after: only
  the removal is left.
- **A file that cannot be read stays** where it is, and its chat opens empty,
  as it would have before.
- **An open conversation is kept in memory and updated in place**, so a new
  message does not read the conversation from the database again. The view is
  dropped when nobody is watching, and rebuilt when another process has
  written (the shared lock reports that).
- **Where the file is.** On Android, in the history folder. On iPhone, in the
  app's own documents (`history_{uid}`), not in the container shared with the
  notification extension: the extension does not open it, and a database held
  open in a shared container can get a suspended app killed by iOS.
- **The Android background handler** opens its own connection to the same
  file. SQLite's write-ahead log lets both read, and the account lock already
  makes them write one at a time.
- **On iPhone the reaction alert loses its quote** once a chat is imported:
  the extension finds no history file and uses the wording it already had for
  that case.
- **Erasing an account** removes the database folder as well.

## Windows (step 3)

- A conversation is read as its newest 200 messages. Scrolling back to the
  oldest shown loads 200 more; jumping to an old message (a search result, a
  quote, a pin) loads up to it and 50 before.
- What a window shows is always the true end of the conversation: a message
  that arrives late with an old send time is not shown at the window's start,
  and a message leaving a full window lets an older one in. A test checks this
  over random changes.
- Search reads whole histories, when a search is made.

## Read flags (issue 180)

- Each message has a read flag. Unread is an indexed count. What this account
  sent, and what its author deleted, counts as read.
- **Why a flag and not a "seen up to here" mark:** a message can arrive late
  with an early place in the conversation (held for a security-code check,
  then released). A mark would count it as seen without it ever being shown.
- The list of seen ids in the preferences file is carried into the flags once,
  then removed from the file. The file keeps mutes, pins, the preview choice
  and which chats have had their first-run baseline.
- The baseline rule is unchanged: when read state starts for a chat, exactly
  the messages already there are marked read, by whoever claims the baseline
  first, so a message arriving meanwhile stays unread.
- Schema version 2 adds a status column, so a count can leave out lines that
  are not readable messages (group notices) without opening each record.

## Cost and size

No server cost: the database is on the phone. The library adds a few megabytes
to the app; to be measured on the first release build.

## Not verified

Performance on a phone, and the library's behaviour on a real iPhone. The
macOS CI job builds the app with it; nothing here was run on a device.
