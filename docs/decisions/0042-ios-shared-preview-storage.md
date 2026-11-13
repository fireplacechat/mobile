# 0042: Shared storage for iOS notification previews

Status: proposed for review. Implements the storage foundation of 0035;
previews remain unavailable until the extension is implemented and tested.
The owner explicitly chose after-first-unlock access for every installation.

## Keychain

The app keeps its existing default access group first, so Firebase Auth's own
keychain records do not move. Fireplace's `flutter_secure_storage_service`
records move to `$(AppIdentifierPrefix)com.fireplacechat.app.shared`. Each
legacy value is copied, read back and compared before its original is
deleted. Identical interrupted copies can be resumed; conflicting copies
are preserved and access fails. A failed migration never opens an empty
fallback store or causes replacement keys to be generated.

Every iOS secret-store operation waits for preparation. Both migrated and
new items use `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, without
iCloud synchronisation. This deliberately permits reads while locked after
the first unlock, and still denies access after reboot before that unlock.
This affects every install, regardless of its preview preference. The native
method channel returns only the resolved access-group name and container
path; keychain values never pass through it.

## History and locking

The existing encrypted history directory, including append logs and encrypted
preferences, moves by one atomic directory rename into
`group.com.fireplacechat.app`. No ciphertext, stored JSON, keys or plaintext
are rewritten. A restart repeats safely. If both source and destination
exist, both are preserved and opening is refused. Migration and protection
changes run only in the app, never in the notification extension.

Files are protected until the first unlock and excluded from backups because
their key is device-only. The original encrypted formats and filenames stay
the same. The app and extension agree on the App Group location.

The existing isolate gate remains necessary: POSIX record locks belong to a
process, so they cannot exclude two Flutter isolates. On iOS the account
gate also holds an exclusive OS file lock. Async release closes its file
descriptor before releasing the isolate gate; shutdown waits for queued
holders. The extension must take the matching fcntl lock for its read-only
snapshot. It must not use flock, which is a different lock mechanism.

Account lock files live in the App Group's `locks/` directory, outside history
directories that account deletion removes. Migration uses a separate
`migration.lock`. Neither side may open and close an additional descriptor
for an account lock while holding it: on POSIX that releases process locks.
The extension will use bounded lock waits and fall back on contention.

## Validation and owner setup

Tests cover independent-process lock exclusion and release on exceptions,
shutdown, keychain copy/read-back/delete interruption and conflicting copies,
operation ordering and migration failure, unchanged history bytes, repeat
migration and preservation of conflicting directories. Native tests run only
through an owner-dispatched Mac workflow; Windows checks cannot prove Apple
keychain or file-protection behavior. A TestFlight upgrade must retain the
existing identity, device, sessions and history, including while locked.

Before a signed build, the owner must enable the App Group on the app's App
ID and run signing setup after merge. The signing lane forces an App Store
profile refresh. [Setup and upgrade checks](../development/ios-previews.md)
give the identifiers and exact owner command. The extension's additional
profile follows with its target. Do not upload using the previous profile.

No server fields, Firestore rules, runtime network calls or dependencies are
added. The extension's fetch, diagnostics and measured memory budget follow
separately. Nothing in this PR selects the Rust backend in production.

References: [Apple keychain sharing](https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps)
and [after-first-unlock device-only protection](https://developer.apple.com/documentation/security/ksecattraccessibleafterfirstunlockthisdeviceonly).

Implementation assisted by OpenAI Codex.
