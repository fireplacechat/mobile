# Deeper day tints, brighter night tints

Each chat colour's soft tint, behind other people's messages, is deeper in
light mode and more colourful in dark mode. The owner chose the values in a
colour-testing page. The fill of your own messages and the coloured names and
links are unchanged.

| Screen | Light | Dark |
| --- | --- | --- |
| A chat with a person's own colour | [compare](light-conversation-peer-color.png) | [compare](dark-conversation-peer-color.png) |
| The colour picker | [compare](light-chat-colors.png) | [compare](dark-chat-colors.png) |
| The highlight after jumping to a message | [compare](light-search-message-location.png) | [compare](dark-search-message-location.png) |
| A reply | [compare](light-messages-reply-sent.png) | [compare](dark-messages-reply-sent.png) |

Each image is the render catalogue before (left) and after (right):
`TZ=UTC flutter test scripts/render/render_screens_test.dart`, written to
`build/renders/`.

The light-mode jump highlight now leans further towards the sender's colour.
Half-way between the two bubble colours sat too close to the deeper tints
(`test/styles/chat_colors_test.dart` checks every pair of colours).
