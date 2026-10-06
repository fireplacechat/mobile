# Roadmap

Plans change, and nothing here is a promise or a date. Ideas and questions are welcome in
[Discussions](https://github.com/fireplacechat/mobile/discussions); work that is ready to pick up is labelled
[`help wanted`](https://github.com/fireplacechat/mobile/labels/help%20wanted) and
[`good first issue`](https://github.com/fireplacechat/mobile/labels/good%20first%20issue).

## Now
- Making the code easier to read and contribute to: a feature-based layout, small focused files, a written architecture map ([docs/architecture.md](architecture.md)).
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
