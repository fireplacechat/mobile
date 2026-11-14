# Roadmap

Plans have no promised dates. The [feature status](roadmap/feature-matrix.md)
describes current source; [open issues](https://github.com/fireplacechat/mobile/issues)
track work and [Discussions](https://github.com/fireplacechat/mobile/discussions)
is for ideas. Work that is ready to pick up is labelled
[`help wanted`](https://github.com/fireplacechat/mobile/labels/help%20wanted) and
[`good first issue`](https://github.com/fireplacechat/mobile/labels/good%20first%20issue).

## Current work

- Prepare the first beta: real-device messaging checks, accessibility, and store setup.
- Build MLS groups across the Rust core, backend and app, following the
  [version 1 specification](protocol/group-chats-v1.md). The current app is 1:1.
- Improve reliability and keep contributor documentation aligned with the code.

## Next

- A clear offline state ("this will send when you are back online"). It must keep
  a definite failure apart from an unknown outcome and never imply an automatic resend.

## Under consideration

Tappable links, compact bubbles with the time inline, attachments, disappearing
messages, chat archive/pin and translations. Each needs its own design first.

## Not planned

- Voice and video calls, stickers and GIFs.
- Typing indicators, read receipts, delivered ticks, online/last seen. Left out on purpose.
- Analytics, crash reporting or any tracking. See [repository rules](../AGENTS.md).
