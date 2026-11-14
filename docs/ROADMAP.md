# Roadmap

Plans have no promised dates. The [feature status](roadmap/feature-matrix.md)
describes current source; [open issues](https://github.com/fireplacechat/mobile/issues)
track work and [Discussions](https://github.com/fireplacechat/mobile/discussions)
is for ideas.

## Current work

- Prepare the first beta: real-device messaging checks, accessibility, and store setup.
- Build MLS groups across the Rust core, backend and app, following the
  [version 1 specification](protocol/group-chats-v1.md). The current app is 1:1.
- Improve reliability and keep contributor documentation aligned with the code.

## Needs a separate design or decision

Attachments, calls, disappearing messages, translations, and richer chat-list
organization have no implementation commitment here. Offline wording must preserve
the distinction between a definite send failure and an unknown publish outcome;
it must not imply automatic resend of an uncertain message.

## Excluded by project policy

Typing indicators, read receipts, delivered ticks, online/last-seen indicators,
analytics and tracking. See [repository rules](../AGENTS.md).
