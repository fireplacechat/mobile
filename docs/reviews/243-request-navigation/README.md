# Returning from an accepted request

Each pair starts on Requests. Tap Accept, then Back. Main is on the left and this change is on the right. The still shows the screen after acceptance; the recording also shows the return to the chat list. The large versions use a width of 320 logical pixels and 200% text.

Run `TZ=UTC RENDER_EMOJI_FONT=/path/to/emoji-font.ttf flutter test scripts/render/request_navigation_test.dart` on each revision with the same render script. Run `python docs/reviews/243-request-navigation/compare.py <before>/build/request-navigation build/request-navigation` on the feature branch. These are Flutter widget renders using fictional local fixtures.
