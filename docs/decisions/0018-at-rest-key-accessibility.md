# 0018: Device-bound iOS key accessibility

Date: 2026-10-07

## Decision

The default secure store explicitly uses `unlocked_this_device` and disables
Keychain synchronization on iOS. This preserves the existing requirement that
the phone be unlocked while preventing newly created items from migrating to
another device through a backup. Android options remain unchanged.

We do not select `first_unlock_this_device`: that would also permit key access
while the phone is locked after its first unlock. Background key access is not a
requirement of the current beta and needs a separate decision before enabling it.
See [Apple's accessibility guidance](https://developer.apple.com/documentation/security/restricting-keychain-item-accessibility)
and [the device-only unlocked class](https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly).

## Limits and verification

Device-only does not mean no backup bytes exist. Apple describes these classes
as protected with the device UID during backup, so they cannot be used on another
device. See [Keychain data protection](https://support.apple.com/guide/security/keychain-data-protection-secb0694df1a/web).

The plugin can find items written under older accessibility classes. Changing
its default does not prove that every existing item has been migrated, and it
cannot invalidate a backup already made. This change protects newly created
items; existing-install migration and same-device/new-device backup restoration
remain native iOS verification items before expanding beyond fresh beta installs.
Do not delete and recreate identity keys automatically to migrate them.

The regression test inspects actual platform-channel options for read, write,
delete and whole-store reset. It proves configuration, not OS backup behavior.
Injected storage remains under the caller's control for tests.
