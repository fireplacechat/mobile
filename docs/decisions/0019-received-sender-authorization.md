# 0019: Check received-message participants locally

Date: 2026-10-07

## Decision

The receiver derives the peer from the existing validated two-part chat ID and
accepts sender UIDs only from that peer or the signed-in account. Invalid chat
IDs and other sender UIDs are ignored before journal replay, pending-send
confirmation, placeholder creation or cryptographic processing.

Firestore rules still enforce membership and sender ownership. The local check
is an additional authorization boundary and does not replace those rules or the
existing device certificate and authenticated-envelope checks. No envelope,
handshake, server field or rule changes are required.

## Consequences

Peer messages, requests and copies from the account's other devices remain
supported. Tests cover rejection without history or key-state changes, valid
participant processing and continued sync progress after rejected messages.

Stored direction remains device-relative for protocol bookkeeping. The public
history stream projects it relative to the account using the authenticated sender
UID, so a linked-device copy of the account's own message is displayed as its own.
This also corrects existing local history on read without rewriting stored ratchet
state or changing the randomized protocol simulation's invariants.
