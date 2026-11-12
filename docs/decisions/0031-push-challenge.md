# 0031: Answer a push challenge

Status: requested by the owner (issue #96), 2026-11-12. Goes with backend
decision 0020. The push handler is not wired here.

## What it does

The server can ask an account to show that it holds a push token this server
already registered. It stores a random token where clients cannot read it,
and sends that token only to the account's own devices, as a data-only push
`{type: rateLimitChallenge, challenge}`. There is no captcha.

`PushChallenge.answer` checks that map. When `type` is `rateLimitChallenge`
and `challenge` is 64 lowercase hex characters, it writes
`users/{uid}/challengeProof/current` as `{token: <challenge>}` with `set()`,
which replaces a proof already there. Any other map is ignored, including a
short, long, or non-hex token. A failed write is reported as not answered.
The error is not thrown to the caller.

The handler in issue #86 will call this and then retry the send. This change
does not receive pushes and does not retry.

## Cost

One Firestore write for each challenge the app accepts. No read. The server
sends a challenge only when its spam policy asks, which it does not yet, so
the write is rare. The stored value is the token from that push. It is not
message text.

Implementation assisted by Grok.
