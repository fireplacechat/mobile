# 0060: A secret in the linking QR code

Date: 2026-11-15. Status: proposed for review.

## Decision

The QR code a new device shows now carries 16 random bytes besides the
fingerprint of its keys. The bytes are made on the new device, kept in memory
while the screen is open, and sent nowhere: not to the server and not to disk.
The approving device reads them from the QR code and puts them into the key
that seals the account identity. The new device opens the response with the
same bytes. A response sealed without them does not open, so the new device
installs an identity only from a device that read its screen.

This ties both directions of linking to the QR code. The fingerprint already
made sure the identity is sealed to the keys on the new device's screen. The
secret makes sure the answer comes from the device that scanned it.

## Format

QR code, version 2:

```
fireplace://link/2/<uid>/<deviceId>/<fingerprint>/<secret>
```

`<secret>` is the 16 bytes in base64url without padding (22 characters). The
other parts are unchanged.

Sealing key:

```
key  = HKDF-SHA-256(ikm = dh || kemShared || secret, salt = empty, info)
info = lp("fireplace/v2/link", uid, deviceId, ek, kemCt, x25519Pub, kemPub)
```

`dh` and `kemShared` are 32 bytes each, so the secret after them needs no
length prefix. `info` is also the associated data, as before. Only the label
changed, from `fireplace/v1/link`. The core accepts a secret of 16 to 64
bytes; the app always makes 16.

The link request on the server, the response fields and the rules are
unchanged. No reads or writes are added.

## Older versions

There is one form. A version with this change does not answer a version 1 QR
code and tells the person to update the new device first. An older version
does not recognise a version 2 QR code. Both devices must be updated before
linking. Nothing stored changes, so devices that are already linked are not
affected.

Keeping the old form for a time would keep the old guarantee for that time,
so it is not kept.

## The typed code

The 6-digit code is still shown on the approving device and typed on the new
one. It no longer carries the guarantee; the secret does. Whether to keep the
step is a separate decision.

## Core

`fireplace-crypto` replaces `fp_link_seal` and `fp_link_open` with
`fp_link_seal_v2` and `fp_link_open_v2`, which take the secret. The names
changed so that a caller built for the old form fails to find the function
rather than calling it with the wrong arguments. The Dart reference
implementation makes the same change, and one known answer is shared between
the two.

## Validation

- Core and Dart reference: a response opens with the right secret and fails
  with a secret that differs in one bit, in length, or is all zeros; a secret
  shorter than 16 or longer than 64 bytes is refused on both sides; the two
  implementations seal the same bytes from the same inputs, and each opens
  the other's response.
- Service: a response sealed to the right keys without the secret is refused
  and nothing is installed, whatever code is typed; the secret is not in the
  request written to the server; two requests have different secrets; a
  version 1 QR code is refused in plain words and no response is written.
- The existing linking tests (fingerprint mismatch, wrong code, expiry,
  second answer, cancellation, timeout) pass unchanged.
