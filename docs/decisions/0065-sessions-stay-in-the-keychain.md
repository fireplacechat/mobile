# 0065: Sessions, the receive journal and cursors stay in the keychain

Date: 2026-11-19. Status: proposed, for the owner to decide. Issue #78, step 5
of decision 0057. No code in this change.

## The question

Decision 0057 moved history into an SQLCipher database and left one step: move
the ratchet sessions, the receive journal and the receive cursors in too, so
that one transaction saves a message, the session it advanced and the cursor
past it. The receive journal would then go.

This note recommends not doing that, and closing step 5.

## Where these live today

All in the Keychain (iPhone) or the Keystore-backed secure store (Android):

- `sess:{device}:{peer}:{peerDevice}`: the ratchet sessions with one peer device.
- `journal:{device}`: at most one open receive journal. Once a message
  authenticates, its effects (the history entry, the advanced session, the
  spent one-time prekey) are first written as one journal record. Applying it
  is idempotent, and it is replayed before anything else is received.
- `cursor:{device}:{chat}`: per chat, the newest message this device has
  finished receiving. It only moves forward.

The one-time prekey's private half is in the secure store as well, and its
public copy is in Firestore.

## Why step 5 does not fit

**The iPhone notification extension reads these items.** To show a preview it
checks that no journal is open, reads the chat's cursor to ask Firestore only
for newer messages, and decrypts with a copy of the stored sessions. It saves
nothing (decision 0043). It reads them from the shared keychain because it
cannot read the database: 0057 keeps `history.db` in the app's own documents,
not in the container shared with the extension, because iOS can kill a
suspended app that holds a database open in a shared container. 0057 also says
the extension does not open the database, to stay inside its memory limit.

So moving sessions, the journal and cursors into the database ends iOS
previews, unless one of these is also done:

1. **The extension opens the database.** The file moves to the shared
   container, the extension links its own SQLCipher, and both sides take the
   existing file lock around every use. This reverses two parts of 0057 and
   brings back the risk 0057 avoided. The extension's memory has not been
   measured on the iPhone X with a database open.
2. **A copy stays in the keychain for the extension.** The database becomes
   the source and the keychain a mirror written after each commit. A crash
   between the two leaves the mirror behind, so the extension can decrypt with
   an old session, and there are two stores to keep consistent again. That is
   the problem the move was meant to remove.

**What the move would gain is small.** The journal is about a hundred lines,
is covered by the randomized chat simulation and the durability and
fault-injection tests. The large gains of
0057 (reading a screenful, indexed unread counts, search) do not depend on it.
The one-time prekey would stay outside any transaction anyway: its public copy
is deleted from Firestore.

## Recommendation

Keep sessions, the receive journal and cursors where they are, and close step
5 of 0057. With step 4 done (search in the database), issue #78 can close.

Look at this again only if the extension needs the database for its own
reasons, for example to quote the message a reaction is to, which 0057 gave
up. That would be its own decision, with the extension's memory measured on
the iPhone X.

## If the owner decides to go ahead instead

Option 1 above is the only one without a second copy. It needs, in order: a
note that reverses those two parts of 0057, measured extension memory, the
file moved into the shared container, a one-time move of every `sess:`,
`journal:` and `cursor:` item into the database (each removed only after the
database has it, safe to stop at any point), the receive path rewritten as one
transaction, and the journal's tests rewritten for it. The randomized chat
simulation and the iOS extension's tests would have to pass unchanged.

## Cost

None. No code change, and no Firestore reads or writes.
