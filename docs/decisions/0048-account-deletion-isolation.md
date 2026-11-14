# 0048: Complete account deletion without erasing other accounts

Status: proposed. Fixes client deletion and scopes local preferences/erasure.

The previous client enumerated `users/{uid}/limits`, although deployed rules
forbid listing counters. Both fresh and resumed deletion therefore failed before
removing the profile/Auth user. Its eventual `SecretStore.clear()` also erased
every account in the installation, while appearance notifiers retained stale
in-memory preferences. Resuming with no initialized session did not erase files.

## Confirmed deletion, bounded cleanup

Keep username/password confirmation and reauthentication. Confirm the UID still
matches before destructive boundaries; coalesce duplicate requests. Set the
existing irreversible `deleting` fence, suspend iOS preview credentials, invalidate
the normal session and drain its work. Freeze/drain that account's preference
writes. No account data is erased on an unrelated startup/crypto/runtime error.

Delete sent-message documents in sender-filtered pages of 400. Delete all
enumerated devices/prekeys, push tokens, the backup, link requests and blocks.
Delete **named** `limits/send`, `limits/chats`, `limits/claims`, and
`challengeProof/current`; do not allow counter/proof listing. No new collections,
deployed function, crypto dependency or protocol/schema migration is introduced.

Erase local data before deleting the username/profile, so local failure retains
the server fence. Release the username only if its stored owner matches. Delete
the Auth account last and explicitly sign out; a different newly selected account
must not be signed out/deleted. Partial failure stays fenced and can be resumed
with the password; no recovery key or successful crypto startup is needed.

## One local account at a time

Enumerate the existing secure store, select exact UID keys and the owner element
of account-scoped trust keys. Derive local device IDs from existing device/bundle
JSON and private-prekey key names. Erase device-prefixed sessions/cursors/journals
as well as UID-specific identity, device, bundle, history/preferences keys,
hidden-chat state, push choices/index and matching iOS preview credentials.
Keep device/bundle/prekey ownership anchors until derived erasure finishes so a failed
keychain delete can retry. Never delete a peer's session merely because its key
contains the target UID as a recipient. Never use the whole-install clear API.

Resolve legacy Documents and iOS App Group history roots directly, without
initializing/migrating a chat session. Under the account lock erase only the
`messages_{uid}` directories, including sidecars, append logs and temp files.
Deletion locks do not write a generation file that would recreate the erased
directory. Reject invalid UID paths/symlinks; leave sibling account directories.
Native shared-keychain migration already copies, verifies, then removes legacy
items; its groups, entitlement requirements and crypto C ABI are unchanged.

Theme, chat colours and send sound now use account-specific local keys. Migrate
the old shared choices to every locally known account without overwriting an
existing personal choice, then remove the shared originals. Deleting one account
resets its UI and signed-out view while preserving the other accounts' inherited
look. Serialized preference writes cannot restore a deleted account after erase.
Opening a surviving account's chat list no longer automatically deletes its
history merely because the other participant deleted their account.

## Backend and validation

The companion backend rules change allows an owner to enumerate their own
device/prekey records and release their own username after an earlier client
already removed the profile. It does not grant new create/update privileges.
Incoming-message reads are denied after the deletion fence/profile removal;
the sender-filtered cleanup query remains allowed. Normal accounts are unchanged.

Model tests reproduce denied counter listing, assert explicit signout and
interrupt/resume every boundary. Storage tests cover all key families, failed
erasure, exact UID/device ownership, both directories and sibling preservation.
Provider tests finish cold pending deletion and verify UI reset, other-account
data preservation and account-switch preference isolation. Real-rule emulator
tests walk the complete cleanup, including the legacy missing-profile state.
Physical signed iPhone verification is still required before release.

Cost: deletion reads/deletes existing account data plus bounded empty-page checks;
each retry deletes four named counter/proof paths even when absent. No recurring
work or new paid service. Local enumeration/migration is device-only. Rule lookup
checks use the existing profile/owner paths. Other people's already-received
local histories, abuse reports and the used invite remain outside this deletion.
