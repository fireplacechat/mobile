# Familiar by design, principled by default

**Draft for the owner.** The goal: anyone who has used a mainstream messenger should feel at home in Fireplace within a minute, and the project should be
free, open source, no ads, no tracking, run for its users, small and dependable, with everything explained in plain words.

## The two halves
**Familiar.** The chat list, bubbles with the time inside, day separators, long-press for actions, forward, reply, emoji, mute, search,
unread badges, formatting with `*` `_` `~`. Nothing here should need explaining.

**Principled.**
- Free for ever. No ads, no tracking, no selling data, no analytics SDKs, no crash reporters that send data away.
- Open. The code, the protocol notes, the decisions (`docs/decisions/`) and the threat model are public, and contributions are welcome.
- Honest. Plain wording; say what is stored and for how long; never claim more than is true.
- Small and dependable. Few features done well; boring reliability; works on cheap phones and slow networks.
- Private by design. The server only holds ciphertext; anything that needs message text runs on the phone.

## Where the two disagree
Most messengers show when you are online, when you are typing and when a message was read. **Fireplace does not** (owner decision): those signals leak your behaviour.
Where a common habit conflicts with privacy, privacy wins, and the app explains why in one line.

## Feature matrix
"State" is what the code does today, from [CHAT_UI_FEATURES.md](chat-ui-features.md) and the review notes. "Fit" is whether it suits Fireplace.

| Feature | Common in messengers | State | Fit and suggestion |
|---|---|---|---|
| Text messages, emoji | yes | works (system keyboard) | have it |
| Bold, italic, strikethrough | single-character markers (`*b*` `_i_` `~s~`) | `**b**` `_i_` `~~s~~` (owner choice) | built on the chat UI branch; consider also accepting single `*` and `~` so habits carry over |
| Monospace / code | triple backtick | not planned | cheap and useful; decide |
| Time inside the bubble, grouped bubbles | yes | time under text; no grouping | **adopt** (inline time, grouping consecutive messages): shorter chats, the familiar look |
| Long-press menu | reply, forward, copy, delete, info | built (copy, forward, select text, report) | have it; add reply and delete later by adding entries to one list |
| Reply / quote | yes | not built | **priority candidate**: it is the most used chat feature after sending; fits privacy (local rendering of a quoted message id) |
| Forward | yes | built | have it |
| Delete for me | yes | not built | later; local only, easy |
| Delete for everyone, edit | yes (time-limited) | not built | later (owner decision); needs protocol design, and honest wording (the other phone may already have a copy) |
| Reactions | yes | not built | decide; small protocol addition |
| Starred messages | yes | not built | local only; cheap |
| Pin chat | yes | not built | local only; cheap |
| Archive chat | yes | not built | local only; cheap |
| Mute | yes | built | have it |
| Unread counts and badge | yes | built | have it (local only; nobody learns you read anything) |
| Typing indicator, online / last seen, blue ticks | yes | **no, by decision** | conflicts with the privacy principle |
| Message notifications | yes | in-app banner built; system push is groundwork only | push needs a server-side sender (not free-plan trivial); decide how to do it without leaking content |
| Search | per chat and global | global search of all message text built | have it; add search inside one chat later |
| Link previews | yes | not built | **do not** build (the previewing phone would contact the site); plain tappable links are enough |
| Tappable links | yes | not built | suggested: detect links and open them in the browser (no confirmation step); needs a link-opening package, owner approval |
| Photos, video, files, voice notes | yes | not built | the biggest gap; needs encrypted attachments and a storage budget on the free plan |
| Stickers, GIFs | yes | not a priority (owner) | later |
| Disappearing messages | yes | no per-chat disappearance timer or automatic deletion guarantee | decide; natural fit for the privacy story |
| Drafts | yes | not saved | cheap, local |
| Groups | yes | not a priority (owner) | later |
| Voice and video calls | yes | not a priority (owner) | later |
| Multi-device | yes | linked devices exist | have it |
| Backup | yes | recovery key restores identity, not old messages | by design; explain clearly |
| Block and report | yes | built | have it |
| Wallpaper and bubble colours | yes | bubble colours built (temporary) | persist locally later |
| Large text, screen readers | yes | built, needs phone testing | keep testing |

## Suggested next slice for "feels familiar"
1. Inline time and grouped bubbles (visual, small, no protocol change).
2. Reply with a quoted message (protocol field for the quoted message id, rendered locally).
3. Drafts, delete for me, pin and archive (local only).
4. Tappable links, then attachments (photos first), then push notifications.
