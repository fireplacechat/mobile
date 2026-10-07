# Roadmap

Plans change, and nothing here is a promise or a date. Ideas and questions are welcome in
[Discussions](https://github.com/fireplacechat/mobile/discussions); work that is ready to pick up is labelled
[`help wanted`](https://github.com/fireplacechat/mobile/labels/help%20wanted) and
[`good first issue`](https://github.com/fireplacechat/mobile/labels/good%20first%20issue).

## Done recently
- The code is organised by feature, in small focused files, with a written architecture map ([docs/architecture.md](architecture.md)) and checks that keep it that way.
- Contributor documents are in place: a Code of Conduct, a contributor license agreement, issue templates and starter issues.

## Now
- Preparing for a first beta on iOS and Android: testing on real devices, accessibility checks, store setup.

## Next
- A clear offline state ("this will send when you are back online").
- Push notifications when the app is closed, once the server-side sender is in place.
- Message editing and deleting, after deciding exactly what those promise.

## Under consideration
- Tappable links.
- Compact message bubbles with the time inline.
- Translations: choosing where strings live, then a translation workflow.
- Stricter static analysis and more immutable state in the code.

## Not planned
- Group chats, voice and video calls, stickers and GIFs.
- Typing indicators, read receipts, "online" or "last seen". These are left out on purpose.
- Analytics, crash reporting or any tracking.
