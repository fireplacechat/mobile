# 0012: message length limit and the ciphertext cap

Status: accepted (owner, 2026-10-05); written after review of `feature/chat-ui-review`.

## Decision
- A message is at most **16,384 characters**, counted as Unicode code points (an emoji is one; combining marks and ZWJ parts count separately). It is enforced
  when typing and pasting, in `ChatService.sendText` (before any key or network work, never by silent truncation), and when forwarding.
- Receivers never trust the sender's count. A message over the limit (another client, an old build, a hostile client) is shown as literal text, clipped to a
  512-character preview with Show all / Show less, never formatted, and never forwarded. Previews, notices and search work on bounded text.
- `Envelope.maxCiphertext` (the receiver's bound on one envelope's ciphertext) is raised from 64 KiB to **128 KiB**. Reason: 16,384 emoji are
  65,536 bytes of UTF-8 before the JSON wrapper, which did not fit in 64 KiB, and 16,384 JSON-escaped control characters need about 98 KiB. The wire
  format, protocol version, authentication labels and fields are unchanged; only the bound on what a receiver will accept grows.

## Consequences and limits
- Builds older than this change reject a received envelope over 64 KiB. Before the first public release this affects nobody; after it, raise the cap only
  with a version note.
- One Firestore document holds one envelope per recipient device and per own other device. A worst-case message (about 137 KB of envelope per device when
  full of escaped control characters, about 94 KB for emoji) reaches the 1 MiB document limit at roughly 7 to 11 devices in total. The rules allow up to 40
  envelopes and nothing caps devices, so a very large message from an account with many devices can be refused by the server. That refusal is a definite
  failure and is reported as "nothing was sent" (see the review fix E1). If many-device accounts become real, cap devices or check the estimated size before sending.
- Expiry metadata alone does not delete server messages (decision 0010); the larger cap does not establish a retention guarantee.
