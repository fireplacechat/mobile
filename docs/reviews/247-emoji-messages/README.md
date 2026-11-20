# Emoji messages

Each comparison shows the same fictional messages on main (left) and this branch (right). The sent and received conversations each show one, two, three and four emoji. The reply example includes a quote and a reaction. The selected example shows the chat's selection controls. The group example uses real group message rows with sender names and avatars. The timestamp uses Ocean for sent messages, Plum for received messages and Forest for the other group member. The hold recordings show the timestamp as the message menu opens. The large example is 320 logical pixels wide with 200% text.

Run `TZ=UTC RENDER_EMOJI_FONT=/path/to/emoji-font.ttf flutter test scripts/render/emoji_messages_test.dart` in both checkouts, using the same render script and font. These images used the Windows Segoe UI Emoji font. Run `python docs/reviews/247-emoji-messages/compare.py <before>/build/emoji-review build/emoji-review` on the feature branch to label the comparisons.
