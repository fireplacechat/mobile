# 0034: Encrypted database, or keep the files

Status: Proposed, for the owner to decide. Issue #78. No code in this change,
and no package is added.

## Today

Each chat is an AES-256-GCM snapshot, plus a log once the chat is long
(decisions 0013 and 0027). The key is `msgkey:<uid>` in the Keychain. Sessions
and the receive journal are their own keychain items. Search, an unread count,
or a jump to an old message reads those files. Rewriting a whole snapshot was
measured at 99 ms for 2,000 messages (0027). The iOS extension (#87) would have
to open the same files, and the same keys, from a second process.

## SQLCipher

Molly keeps local history in SQLCipher. The database key is a random 32-byte
value. In the current app that key is sealed in the Android keystore
(`DatabaseSecretProvider`). It is not wrapped by the passphrase. The passphrase
wraps a different secret, described in decision 0033.

The Flutter package that vendors this is `sqflite_sqlcipher` 3.4.1, with
SQLCipher 4.10.0. The plugin's pub page reports an MIT licence; the repository
licence file is BSD-2-Clause. SQLCipher itself is BSD-3-Clause. Those licences
can sit beside the AGPL. The plugin is a local library. Its description has no
server and no telemetry. Approving it still includes a look at the native code.
Android release builds need a ProGuard keep rule for `net.sqlcipher`. The
plugin supports Android, iOS and macOS. It does not support Windows, Linux or
the web, which this app does not ship.

This note does not include a measured build size. The cost is the native
SQLCipher binaries. Measure a release build of our app before approving the
package.

What it would fix:

- search, unread counts and paging without loading a whole chat
- one file and one key for the iOS extension, instead of every history file
  and the session items
- one transaction per saved message, which decision 0027 names as the further
  step that needs a database package

What it costs, besides the size:

- a new package, which always needs the owner's approval
- a native build on both phones, and the ProGuard rule
- a migration. Read every current file, write the rows, check the counts, and
  only then delete the files. A failed migration leaves the files (decision
  0013). Tests cover a snapshot, a log, a log cut short by a crash, and an
  empty chat.
- the passphrase lock (0033) would wrap this database key the same way it
  wraps `msgkey:<uid>`

## Keep the files, and add an index

One more encrypted file can hold chat id, message id, time and whether it is
unread. Search and unread counts then read the index, not the whole chat. No
new package. The extension would still have to understand our files and our
keys. This does less for #87 than one database does.

## Recommendation

Keep the files. Add the index when search or unread counts need it. That does
not need a new package.

Use SQLCipher only if the #87 spike finds that the extension cannot work from
the files. That needs the owner's approval, a measured build size, the native
review, and the migration tests above. This note does not add the package.

Drafted by Grok.
